//
//  SyncServer+UploadExtras.swift
//  
//
//  Created by Christopher G Prince on 2/25/21.
//

import Foundation

extension SyncServer {
    func reachedMaxUploadFileGroups() throws -> Bool {
        let number = try UploadObjectTracker.numberFileGroupsUploading(db: db)
        return number >= configuration.maxConcurrentFileGroupUploads
    }
    
    // Check to see if there are deferred uploads waiting. If no, the returned array is empty.
    func deferredUploadsWaiting() throws -> [UploadObjectTracker.UploadWithStatus] {
        // We consider all of these to be vN: Because, once a v0 upload completes for an object, the trackers are immediately removed (see cleanupAfterUploadCompleted).
        let vNCompletedUploads = try UploadObjectTracker.uploadsMatching(filePredicate: {$0.status == .uploaded}, scope: .all, db: db)
        
        guard (vNCompletedUploads.compactMap { $0.object.v0Upload }).count == vNCompletedUploads.count else {
            throw SyncServerError.internalError("v0Upload not set in some UploadObjectTracker")
        }

        let v0 = vNCompletedUploads.filter { $0.object.v0Upload == true }
        
        guard v0.count == 0 else {
            throw SyncServerError.internalError("Somehow, there are v0 uploads with all trackers uploaded, but not yet removed.")
        }
        
        return vNCompletedUploads
    }
    
    // This can take appreciable time to complete-- it *synchronously* makes requests to server endpoint(s). You probably want to use DispatchQueue to asynchronously let this do it's work.
    // This does *not* call SyncServer delegate methods. You may want to report errors thrown using SyncServer delegate methods if needed after calling this.
    // On success, returns the UUID's of the file groups of deferred uploads detected as successfully completed.
    func checkOnDeferredUploads() throws -> [UUID] {
        let vNCompletedUploads = try serialQueue.sync {
            return try self.deferredUploadsWaiting()
        }
        
        guard vNCompletedUploads.count > 0 else {
            // This just means that there are no vN uploads we are waiting for to have their final deferred upload completed. It's the typical expected case when calling the current method.
            return []
        }
                
        // The non-error completion result is the UUID of the file group that was uploaded if it's deferral is completed.
        func apply(upload: UploadObjectTracker.UploadWithStatus, completion: @escaping (Swift.Result<UUID?, Error>) -> ()) {

            guard let deferredUploadId = upload.object.deferredUploadId else {
                completion(.failure(SyncServerError.internalError("checkOnDeferredUploads: Did not have deferredUploadId.")))
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
                        completion(.success(nil))
                    case .completed:
                        do {
                            try self.cleanupAfterVNUploadCompleted(uploadObjectTrackerId: uploadObjectTrackerId)
                            completion(.success(upload.object.fileGroupUUID))
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
        
        let (fileGroupUUIDs, errors) = vNCompletedUploads.synchronouslyRun(apply: apply)
        guard errors.count == 0 else {
            throw SyncServerError.internalError("synchronouslyRun: \(errors)")
        }
                
        return fileGroupUUIDs.compactMap {$0}
    }
}
