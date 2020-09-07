//
//  SyncServer+Sync.swift
//  
//
//  Created by Christopher G Prince on 9/6/20.
//

import Foundation

extension SyncServer {
    // Only re-check of uploads so far. This handles vN uploads only. v0 uploads are always handled in `queueObject`.
    func triggerUploads() throws {
        let notStartedUploads = try UploadObjectTracker.uploadsWith(status: .notStarted, db: db)
        guard notStartedUploads.count > 0 else {
            return
        }
        
        // What uploads are currently in-progress?
        let inProgress = try UploadObjectTracker.uploadsWith(status: .uploading, db: db)
        let fileGroupsInProgress = Set<UUID>(inProgress.map { $0.object.fileGroupUUID })
        
        var current = Set<UUID>()
        var toTrigger = [UploadObjectTracker.UploadWithStatus]()
        
        for upload in notStartedUploads {
            // filter out any duplicate fileGroupUUID's-- Don't want parallel uploads for the same declared object.
            guard !current.contains(upload.object.fileGroupUUID) else {
                continue
            }
            
            // Similarly, if the file group is actively uploading, don't trigger another for the same file group.
            guard !fileGroupsInProgress.contains(upload.object.fileGroupUUID) else {
                continue
            }
            
            current.insert(upload.object.fileGroupUUID)
            toTrigger += [upload]
        }
        
        guard toTrigger.count > 0 else {
            return
        }
        
        // Now can actually trigger the uploads.
        
        for uploadObject in toTrigger {
            let uploadCount = Int32(uploadObject.files.count)
            let declaredObject = try DeclaredObjectModel.lookupDeclarableObject(declObjectId: uploadObject.object.fileGroupUUID, db: db)

            for (uploadIndex, file) in uploadObject.files.enumerated() {
                try singleUpload(declaration: declaredObject, fileUUID: file.fileUUID, newFile: false, uploadIndex: Int32(uploadIndex + 1), uploadCount: uploadCount)
                
            }
        }
    }
    
    // JUST A DRAFT!!! Needs to work on all vNCompletedUploads.
    func checkOnDeferredUploads() throws {
        let vNCompletedUploads = try UploadObjectTracker.uploadsWith(status: .uploaded, db: db)
        let v0 = vNCompletedUploads.filter { $0.object.v0Upload }
        guard v0.count == 0 else {
            throw SyncServerError.internalError("Somehow, there are v0 uploads with all trackers uploaded, but not yet removed.")
        }
        
        guard vNCompletedUploads.count > 0 else {
            return
        }
        
        let vNCompletedUpload = vNCompletedUploads[0]
        guard let deferredUploadId = vNCompletedUpload.object.deferredUploadId else {
            throw SyncServerError.internalError("Did not have deferredUploadId.")
        }
        
        guard let uploadObjectTrackerId = vNCompletedUpload.object.id else {
            throw SyncServerError.internalError("Did not have tracker object id.")
        }
        
        api.getUploadsResults(deferredUploadId: deferredUploadId) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                self.delegate.error(self, error: error)
            case .success(let status):
                switch status {
                case .error:
                    self.delegate.error(self, error:
                        SyncServerError.internalError("Error reported from getUploadsResults."))
                case .pendingChange, .pendingDeletion:
                    break
                case .completed:
                    do {
                        try self.cleanupAfterVNUploadCompleted(uploadObjectTrackerId: uploadObjectTrackerId)
                        DispatchQueue.main.async {
                            self.delegate.deferredUploadCompleted(self)
                        }
                    } catch let error {
                        self.delegate.error(self, error: error)
                    }
                case .none:
                    break
                }
            }
        }
    }
}
