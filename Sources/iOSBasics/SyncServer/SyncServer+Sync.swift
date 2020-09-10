//
//  SyncServer+Sync.swift
//  
//
//  Created by Christopher G Prince on 9/6/20.
//

import Foundation
import SQLite

extension SyncServer {
    // Only re-check of uploads so far. This handles vN uploads only. v0 uploads are always handled in `queueObject`.
    func triggerUploads() throws {
        let notStartedUploads = try UploadObjectTracker.allUploadsWith(status: .notStarted, db: db)
        guard notStartedUploads.count > 0 else {
            return
        }
        
        // What uploads are currently in-progress?
        let inProgress = try UploadObjectTracker.allUploadsWith(status: .uploading, db: db)
        let fileGroupsInProgress = Set<UUID>(inProgress.map { $0.object.fileGroupUUID })
        
        // These are the objects we want to `exclude` from uploading. Start off with the file groups actively uploading. Don't want parallel uploads for the same file group.
        var currentObjects = fileGroupsInProgress
        
        var toTrigger = [UploadObjectTracker.UploadWithStatus]()
        
        for upload in notStartedUploads {
            // Don't want parallel uploads for the same declared object.
            guard !currentObjects.contains(upload.object.fileGroupUUID) else {
                continue
            }
            
            currentObjects.insert(upload.object.fileGroupUUID)
            toTrigger += [upload]
        }
        
        guard toTrigger.count > 0 else {
            return
        }
        
        // Now can actually trigger the uploads.
        
        for uploadObject in toTrigger {
            let uploadCount = Int32(uploadObject.files.count)
            let declaredObject = try DeclaredObjectModel.lookupDeclarableObject(declObjectId: uploadObject.object.fileGroupUUID, db: db)
            
            guard let objectId = uploadObject.object.id else {
                throw SyncServerError.internalError("Could not get object id")
            }
            
            let fileUUIDs = uploadObject.files.map { $0.fileUUID }
            guard let versions = try DirectoryEntry.versionOfAllFiles(fileUUIDs: fileUUIDs, db: db) else {
                throw SyncServerError.attemptToQueueUploadOfVNAndV0Files
            }
            
            let v0Upload = versions == .v0
            try uploadObject.object.update(setters:
                UploadObjectTracker.v0UploadField.description <- v0Upload)
            
            for (uploadIndex, file) in uploadObject.files.enumerated() {
                try singleUpload(declaration: declaredObject, fileUUID: file.fileUUID, v0Upload: v0Upload, objectTrackerId: objectId, uploadIndex: Int32(uploadIndex + 1), uploadCount: uploadCount)
            }
        }
    }

    // This can take appreciable time to complete-- it *synchronously* makes requests to server endpoint(s). You probably want to use DispatchQueue to asynchronously let this do it's work.
    // This does *not* call SyncServer delegate methods. You may want to report errors thrown using SyncServer delegate methods if needed after calling this.
    // On success, returns the number of deferred uploads detected as successfully completed.
    func checkOnDeferredUploads() throws -> Int {
        let vNCompletedUploads = try UploadObjectTracker.allUploadsWith(status: .uploaded, db: db)
        
        guard (vNCompletedUploads.compactMap { $0.object.v0Upload }).count == vNCompletedUploads.count else {
            throw SyncServerError.internalError("v0Upload not set in some UploadObjectTracker")
        }

        let v0 = vNCompletedUploads.filter { $0.object.v0Upload == true }
        
        guard v0.count == 0 else {
            throw SyncServerError.internalError("Somehow, there are v0 uploads with all trackers uploaded, but not yet removed.")
        }
        
        guard vNCompletedUploads.count > 0 else {
            // This just means that there are no vN uploads we are waiting for to have their final deferred upload completed. It's the typical expected case when calling the current method.
            return 0
        }
        
        var numberSuccessfullyCompleted = 0
        
        func apply(upload: UploadObjectTracker.UploadWithStatus, completion: @escaping (Swift.Result<Void, Error>) -> ()) {

            guard let deferredUploadId = upload.object.deferredUploadId else {
                completion(.failure(SyncServerError.internalError("Did not have deferredUploadId.")))
                return
            }
            
            guard let uploadObjectTrackerId = upload.object.id else {
                completion(.failure(SyncServerError.internalError("Did not have tracker object id.")))
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
                            try self.cleanupAfterVNUploadCompleted(uploadObjectTrackerId: uploadObjectTrackerId)
                            numberSuccessfullyCompleted += 1
                            completion(.success(()))
                        } catch let error {
                            completion(.failure(error))
                        }
                    case .none:
                        // This indicates no record was found on the server. This should *not* happen.
                        completion(.failure(
                            SyncServerError.internalError("No record of deferred upload found on server.")))
                    }
                }
            }
        }
        
        let (_, errors) = vNCompletedUploads.synchronouslyRun(apply: apply)
        guard errors.count == 0 else {
            throw SyncServerError.internalError("synchronouslyRun: \(errors)")
        }
        
        return numberSuccessfullyCompleted
    }
}
