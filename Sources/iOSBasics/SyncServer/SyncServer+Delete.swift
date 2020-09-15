
import Foundation
import SQLite

extension SyncServer {
    func deleteHelper<DECL: DeclarableObject>(object: DECL) throws {
        // Ensure this DeclaredObject has been registered before.
        let declarableObject = try DeclaredObjectModel.lookupDeclarableObject(declObjectId: object.fileGroupUUID, db: db)
        
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
        
        let tracker = try UploadDeletionTracker(db: db, uuid: object.fileGroupUUID, deletionType: .fileGroupUUID, deferredUploadId: 0, status: .deleting)
        try tracker.insert()
        
        let file = ServerAPI.DeletionFile.fileGroupUUID(
            object.fileGroupUUID.uuidString)
        api.uploadDeletion(file: file, sharingGroupUUID: object.sharingGroupUUID.uuidString) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let deletionResult):
                switch deletionResult {
                case .fileAlreadyDeleted:
                    #warning("Can the server endpoint be changed so that on a second call it (at least sometimes) can send back the deferredUploadId?")
                    self.completeInitialDeletion(tracker: tracker, deferredUploadId: nil)
                    
                case .fileDeleted(deferredUploadId: let deferredUploadId):
                    self.completeInitialDeletion(tracker: tracker, deferredUploadId: deferredUploadId)
                }

            case .failure(let error):
                self.delegator { [weak self] delegate in
                    guard let self = self else { return }
                    delegate.error(self, error: error)
                }
                
                do {
                    try tracker.update(setters:
                    UploadDeletionTracker.statusField.description <- .notStarted)
                } catch let error {
                    self.delegator { [weak self] delegate in
                        guard let self = self else { return }
                        delegate.error(self, error: error)
                    }
                }
            }
        }
    }
    
    private func completeInitialDeletion(tracker: UploadDeletionTracker, deferredUploadId: Int64?) {
        do {
            if let deferredUploadId = deferredUploadId {
                try tracker.update(setters:
                    UploadDeletionTracker.deferredUploadIdField.description
                        <- deferredUploadId,
                    UploadDeletionTracker.statusField.description
                        <- .waitingForDeferredDeletion)
            }
            else {
                try tracker.update(setters:
                    UploadDeletionTracker.statusField.description <- .done)
            }
        } catch let error {
            _ = try? tracker.update(setters:
                UploadDeletionTracker.statusField.description <- .notStarted)
            self.delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.error(self, error: error)
            }
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
        
        func apply(deletion: UploadDeletionTracker, completion: @escaping (Swift.Result<Void, Error>) -> ()) {

            guard let deferredUploadId = deletion.deferredUploadId else {
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
                            try self.finishAfterDeletion(deletion: deletion)
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
    
    private func finishAfterDeletion(deletion: UploadDeletionTracker) throws {
        guard deletion.deletionType == .fileGroupUUID else {
            throw SyncServerError.internalError("Didn't have file group deletion type.")
        }
        
        let entries = try DirectoryEntry.fetch(db: db, where:
            DirectoryEntry.fileGroupUUIDField.description == deletion.uuid)
        for entry in entries {
            try entry.update(setters:
                DirectoryEntry.deletedLocallyField.description <- true,
                DirectoryEntry.deletedOnServerField.description <- true)
        }
        
        try deletion.delete()
    }
}
