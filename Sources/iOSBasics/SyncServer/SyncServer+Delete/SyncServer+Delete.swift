
import Foundation
import SQLite

/*
extension SyncServer {
    // This currently only supports `deletionType` (see UploadDeletionTracker) of `fileGroupUUID`.
    func deleteHelper<DECL: DeclarableObject>(object: DECL) throws {
        // Ensure this DeclaredObject has been registered before.
        let declarableObject:ObjectDeclaration = try DeclaredObjectModel.lookupDeclarableObject(fileGroupUUID: object.fileGroupUUID, db: db)
        
        guard declarableObject.declCompare(to: object) else {
            throw SyncServerError.attemptToDeleteObjectWithInvalidDeclaration
        }
        
        // Make sure no files deleted already.
        let fileUUIDs = object.declaredFiles.map { $0.uuid }
        guard !(try DirectoryEntry.anyFileIsDeleted(fileUUIDs: fileUUIDs, db: db)) else {
            throw SyncServerError.attemptToDeleteAnAlreadyDeletedFile
        }
        
        if let _ = try UploadDeletionTracker.fetchSingleRow(db: db, where: UploadDeletionTracker.uuidField.description == object.fileGroupUUID) {
            throw SyncServerError.attemptToDeleteAnAlreadyDeletedFile
        }
        
        let tracker = try UploadDeletionTracker(db: db, uuid: object.fileGroupUUID, deletionType: .fileGroupUUID, status: .notStarted)
        try tracker.insert()
        
        guard let trackerId = tracker.id else {
            throw SyncServerError.internalError("No tracker id")
        }
        
        let file = ServerAPI.DeletionFile.fileGroupUUID(
            object.fileGroupUUID.uuidString)
        
        // Queue the deletion request.
        if let error = api.uploadDeletion(file: file, sharingGroupUUID: object.sharingGroupUUID.uuidString, trackerId: trackerId) {
            // As with uploads and downloads, don't make this a fatal error. We can restart this later.
            delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.error(self, error: .error(error))
            }
        }
        else {
            try tracker.update(setters: UploadDeletionTracker.statusField.description <- .deleting)
        }
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
                guard tracker.deletionType == .fileGroupUUID else {
                    reportError(SyncServerError.internalError("UploadDeletionTracker did not have expected fileGroupUUID type"))
                    return
                }
                
                let entries = try DirectoryEntry.fetch(db: db, where: DirectoryEntry.fileGroupUUIDField.description == tracker.uuid)

                guard entries.count > 0 else {
                    throw SyncServerError.internalError("UploadDeletionTracker did not have expected fileGroupUUID type")
                }
                
                for entry in entries {
                    try entry.update(setters: DirectoryEntry.deletedLocallyField.description <- true)
                    try entry.update(setters: DirectoryEntry.deletedOnServerField.description <- true)
                }
                    
                // Since we don't have a `deferredUploadId`, and thus can't wait for the deferred deletion, delete the tracker.
                try tracker.delete()
            }
        } catch let error {
            _ = try? tracker.update(setters:
                UploadDeletionTracker.statusField.description <- .notStarted)
            reportError(error)
            return
        }
        
        self.delegator { [weak self] delegate in
            guard let self = self else { return }
            delegate.deletionCompleted(self)
        }
    }
    
    // This can take appreciable time to complete-- it *synchronously* makes requests to server endpoint(s). You probably want to use DispatchQueue to asynchronously let this do it's work.
    // This does *not* call SyncServer delegate methods. You may want to report errors thrown using SyncServer delegate methods if needed after calling this.
    // On success, returns the number of deferred deletions detected as successfully completed.
    func checkOnDeferredDeletions() throws -> Int {
        let deletions = try UploadDeletionTracker.fetch(db: db, where: UploadDeletionTracker.statusField.description == .waitingForDeferredDeletion)
        
        guard deletions.count > 0 else {
            return 0
        }
        
        var numberSuccessfullyCompleted = 0
        
        func apply(tracker: UploadDeletionTracker, completion: @escaping (Swift.Result<Void, Error>) -> ()) {

            guard let deferredUploadId = tracker.deferredUploadId else {
                completion(.failure(SyncServerError.internalError("Did not have deferredUploadId.")))
                return
            }
                        
            api.getUploadsResults(deferredUploadId: deferredUploadId) { [weak self] result in
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
                        completion(.success(()))
                        
                    case .completed:
                        do {
                            try self.finishAfterDeletion(tracker: tracker)
                            numberSuccessfullyCompleted += 1
                            completion(.success(()))
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
        
        let (_, errors) = deletions.synchronouslyRun(apply: apply)
        guard errors.count == 0 else {
            throw SyncServerError.internalError("synchronouslyRun: \(errors)")
        }
        
        return numberSuccessfullyCompleted
    }
    
    private func finishAfterDeletion(tracker: UploadDeletionTracker) throws {
        guard tracker.deletionType == .fileGroupUUID else {
            throw SyncServerError.internalError("Didn't have file group deletion type.")
        }
        
        let entries = try DirectoryEntry.fetch(db: db, where:
            DirectoryEntry.fileGroupUUIDField.description == tracker.uuid)
        for entry in entries {
            // Deletion commanded locally-- mark both flags as true.
            try entry.update(setters:
                DirectoryEntry.deletedLocallyField.description <- true,
                DirectoryEntry.deletedOnServerField.description <- true)
        }
        
        try tracker.delete()
    }
}
*/
