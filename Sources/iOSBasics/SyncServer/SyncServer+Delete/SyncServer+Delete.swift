
import Foundation
import SQLite
import iOSShared

extension SyncServer {
    // This currently only supports a `deletionType` (see UploadDeletionTracker) of `fileGroupUUID`.
    func deleteHelper(object fileGroupUUID: UUID, pushNotificationMessage: String?) throws {
        guard let objectInfo = try DirectoryObjectEntry.lookup(fileGroupUUID: fileGroupUUID, db: db) else {
            throw SyncServerError.noObject
        }
        
        guard let sharingEntry = try SharingEntry.fetchSingleRow(db: db, where: SharingEntry.sharingGroupUUIDField.description == objectInfo.objectEntry.sharingGroupUUID) else {
            throw SyncServerError.sharingGroupNotFound
        }
        
        guard !sharingEntry.deleted else {
            throw SyncServerError.sharingGroupDeleted
        }
        
        guard !objectInfo.objectEntry.deletedLocally && !objectInfo.objectEntry.deletedOnServer else {
            throw SyncServerError.attemptToDeleteAnAlreadyDeletedFile
        }

        let deletedFileEntries = objectInfo.allFileEntries.filter {$0.deletedLocally || $0.deletedOnServer}
        
        // Make sure no files deleted already.
        guard deletedFileEntries.count == 0 else {
            throw SyncServerError.attemptToDeleteAnAlreadyDeletedFile
        }
        
        if let _ = try UploadDeletionTracker.fetchSingleRow(db: db, where: UploadDeletionTracker.uuidField.description == objectInfo.objectEntry.fileGroupUUID) {
            throw SyncServerError.attemptToDeleteAnAlreadyDeletedFile
        }
        
        let uploads = try UploadObjectTracker.fetch(db: db, where: UploadObjectTracker.fileGroupUUIDField.description == fileGroupUUID)
        let pendingUploads = uploads.count > 0
        
        let downloads = try DownloadObjectTracker.fetch(db: db, where: DownloadObjectTracker.fileGroupUUIDField.description == fileGroupUUID)
        let pendingDownloads = downloads.count > 0
        
        let tracker = try UploadDeletionTracker(db: db, uuid: objectInfo.objectEntry.fileGroupUUID, deletionType: .fileGroupUUID, status: .notStarted, pushNotificationMessage: pushNotificationMessage)
        try tracker.insert()
        
        guard !pendingUploads &&
            !pendingDownloads &&
            requestable.canMakeNetworkRequests else {
            return
        }
        
        try startSingleDeletion(tracker: tracker)
    }
    
    func completeInitialDeletion(tracker: UploadDeletionTracker, deferredUploadId: Int64?) {
        do {
            if let deferredUploadId = deferredUploadId {
                try tracker.update(setters:
                    UploadDeletionTracker.deferredUploadIdField.description
                        <- deferredUploadId,
                    UploadDeletionTracker.statusField.description
                        <- .waitingForDeferredDeletion)
            }
            else {
                try finishAfterDeletion(tracker: tracker)
            }
        } catch let error {
            _ = try? tracker.update(setters:
                UploadDeletionTracker.statusField.description <- .notStarted,
                UploadDeletionTracker.expiryField.description <- nil)
            reportError(error)
            return
        }
        
        // This is error reporting for the `delegate.deletionCompleted(self, forObjectWith: tracker.uuid)` call, which assumes it's dealing with a fileGroupUUID.
        if tracker.deletionType != .fileGroupUUID {
            reportError(SyncServerError.internalError("tracker.deletionType not fileGroupUUID!"))
        }
        
        self.delegator { [weak self] delegate in
            guard let self = self else { return }
            delegate.deletionCompleted(self, forObjectWith: tracker.uuid)
        }
    }
    
    // This can take appreciable time to complete-- it *synchronously* makes requests to server endpoint(s). You probably want to use DispatchQueue to asynchronously let this do it's work.
    // This does *not* call SyncServer delegate methods. You may want to report errors thrown using SyncServer delegate methods if needed after calling this.
    // On success, returns the file group UUID's of deferred deletions detected as successfully completed.
    func checkOnDeferredDeletions() throws -> [UUID] {
        let deletions = try serialQueue.sync {
            return try UploadDeletionTracker.fetch(db: db, where: UploadDeletionTracker.statusField.description == .waitingForDeferredDeletion)
        }
        
        guard deletions.count > 0 else {
            return []
        }
                
        func apply(tracker: UploadDeletionTracker, completion: @escaping (Swift.Result<UUID?, Error>) -> ()) {

            guard let deferredUploadId = tracker.deferredUploadId else {
                completion(.failure(SyncServerError.internalError("checkOnDeferredDeletions: Did not have deferredUploadId.")))
                return
            }
            
            guard tracker.deletionType == .fileGroupUUID else {
                completion(.failure(SyncServerError.internalError("checkOnDeferredDeletions: Did not have deletionType == .fileGroupUUID.")))
                return
            }
            
            api.getUploadsResults(usingId: .deferredUploadId(deferredUploadId)) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                    
                case .success(let status):
                    switch status {
                    case .error:
                        completion(.failure(
                            SyncServerError.internalError("Error reported within the `success` from getUploadsResults.")))
                            
                    case .pendingChange, .pendingDeletion:
                        // A "success" only in the sense of non-failure. The deferred upload is not completed, so not doing a cleanup yet.
                        completion(.success(nil))
                        
                    case .completed:
                        do {
                            try self.finishAfterDeletion(tracker: tracker)
                            completion(.success(tracker.uuid))
                        } catch let error {
                            completion(.failure(error))
                        }
                        
                    case .none:
                        // This indicates no record was found on the server. This should *not* happen.
                        completion(.failure(
                            SyncServerError.internalError("No record of deferred deletion found on server.")))
                    }
                }
            }
        }
        
        let (fileGroupUUIDs, errors) = deletions.synchronouslyRun(apply: apply)
        guard errors.count == 0 else {
            throw SyncServerError.internalError("synchronouslyRun: \(errors)")
        }
        
        return fileGroupUUIDs.compactMap {$0}
    }
    
    private func finishAfterDeletion(tracker: UploadDeletionTracker) throws {
        guard tracker.deletionType == .fileGroupUUID else {
            reportError(SyncServerError.internalError("UploadDeletionTracker did not have expected fileGroupUUID type"))
            return
        }
        
        let fileEntries = try DirectoryFileEntry.fetch(db: db, where: DirectoryFileEntry.fileGroupUUIDField.description == tracker.uuid)
        guard let objectEntry = try DirectoryObjectEntry.fetchSingleRow(db: db, where: DirectoryObjectEntry.fileGroupUUIDField.description == tracker.uuid) else {
            throw SyncServerError.internalError("Could not find DirectoryObjectEntry")
        }

        guard fileEntries.count > 0 else {
            throw SyncServerError.internalError("UploadDeletionTracker did not have expected fileGroupUUID type")
        }
        
        for entry in fileEntries {
            try entry.update(setters:
                DirectoryFileEntry.deletedLocallyField.description <- true,
                DirectoryFileEntry.deletedOnServerField.description <- true)
        }
        
        try objectEntry.update(setters:
            DirectoryObjectEntry.deletedLocallyField.description <- true,
            DirectoryObjectEntry.deletedOnServerField.description <- true)
            
        // Since we don't have a `deferredUploadId`, and thus can't wait for the deferred deletion, delete the tracker.
        try tracker.delete()
        
        let sharingGroupUUID = try tracker.getSharingGroup()
        
        if let pushNotificationMessage = tracker.pushNotificationMessage {
            api.sendPushNotification(pushNotificationMessage, sharingGroupUUID: sharingGroupUUID) { [weak self] error in
                if let error = error {
                    self?.reportError(SyncServerError.internalError("Failed sending push notification"))
                    logger.error("\(error)")
                    return
                }
            }
        }
    }
}
