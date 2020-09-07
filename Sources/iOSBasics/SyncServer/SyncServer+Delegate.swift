import Foundation
import ServerShared
import iOSShared
import iOSSignIn
import SQLite

extension SyncServer: ServerAPIDelegate {
    func error(_ delegated: AnyObject, error: Error?) {
        delegator { [weak self] delegate in
            guard let self = self else { return }
            delegate.error(self, error: error)
        }
    }
    
    func hasher(_ delegated: AnyObject, forCloudStorageType cloudStorageType: CloudStorageType) throws -> CloudStorageHashing {
        return try hashingManager.hashFor(cloudStorageType: cloudStorageType)
    }
    
    func credentialsForNetworkRequests(_ delegated: AnyObject) throws -> GenericCredentials {
        return try credentialsDelegate.credentialsForServerRequests(self)
    }
    
    func deviceUUID(_ delegated: AnyObject) -> UUID {
        return configuration.deviceUUID
    }
    
    func uploadCompleted(_ delegated: AnyObject, result: Swift.Result<UploadFileResult, Error>) {
        logger.debug("uploadCompleted: \(result)")

        switch result {
        case .failure(let error):
            delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.error(self, error: error)
            }
            
        case .success(let uploadFileResult):
            switch uploadFileResult {
            case .gone:
                // TODO: Need the file uuid here too. And the uploadObjectTrackerId.
                break
                
            case .success(let trackerId, let uploadResult):
                do {
                    try cleanupAfterUploadCompleted(uploadObjectTrackerId: trackerId, fileUUID: uploadResult.fileUUID, result: uploadResult)
                } catch let error {
                    delegator { [weak self] delegate in
                        guard let self = self else { return }
                        delegate.error(self, error: error)
                    }
                }
                
                delegator { [weak self] delegate in
                    guard let self = self else { return }
                    delegate.uploadCompleted(self, result: uploadFileResult)
                }
            }
        }
    }
    
    func downloadCompleted(_ delegated: AnyObject, result: Swift.Result<DownloadFileResult, Error>) {
        assert(false)
    }
}

extension SyncServer {
    func cleanupAfterUploadCompleted(uploadObjectTrackerId: Int64, fileUUID: UUID, result: UploadFileResult.Upload) throws {
    
        // For v0 uploads: Only mark the upload as done for the file tracker. Wait until *all* object files have been uploaded until cleanup.
        
        // For vN uploads: Wait until the deferred upload completion to cleanup.
    
        // There can be more than one row in UploadFileTracker with the same fileUUID here because we can queue the same upload multiple times. Therefore, need to also search by uploadObjectTrackerId.
        guard let fileTracker = try UploadFileTracker.fetchSingleRow(db: db, where: fileUUID == UploadFileTracker.fileUUIDField.description &&
            uploadObjectTrackerId == UploadFileTracker.uploadObjectTrackerIdField.description) else {
            throw SyncServerError.internalError("Problem in fetchSingleRow for UploadFileTracker")
        }

        guard let objectTracker = try UploadObjectTracker.fetchSingleRow(db: db, where: uploadObjectTrackerId == UploadObjectTracker.idField.description) else {
            throw SyncServerError.internalError("Problem in fetchSingleRow for UploadObjectTracker")
        }

        try fileTracker.update(setters:
            UploadFileTracker.statusField.description <- .uploaded)
        
        if objectTracker.v0Upload {
            // Have all uploads successfully completed? If so, can delete all trackers, including those for files and the overall object.
            let fileTrackers = try objectTracker.dependentFileTrackers()
            let remainingUploads = fileTrackers.filter {$0.status != .uploaded}
            
            if remainingUploads.count == 0 {
                try deleteTrackers(fileTrackers: fileTrackers, objectTracker: objectTracker)
                
                guard result.uploadsFinished == .v0UploadsFinished else {
                    throw SyncServerError.internalError("Did not get v0UploadsFinished when expected.")
                }
            }
        }
        else {
            // Need to wait on final cleanup until poll for deferred uploads indicates full completion.
            if result.uploadsFinished == .vNUploadsTransferPending {
                logger.debug("result.deferredUploadId: \(String(describing: result.deferredUploadId))")
                try objectTracker.update(setters: UploadObjectTracker.deferredUploadIdField.description <- result.deferredUploadId)
            }
            
            logger.debug("vN upload: result.uploadsFinished: \(result.uploadsFinished)")
        }
    }
    
    func deleteTrackers(fileTrackers: [UploadFileTracker], objectTracker: UploadObjectTracker) throws {
        for fileTracker in fileTrackers {
            if fileTracker.uploadCopy {
                guard let url = fileTracker.localURL else {
                    throw SyncServerError.internalError("Did not have URL")
                }
                try FileManager.default.removeItem(at: url)
            }
            try fileTracker.delete()
        }
        
        try objectTracker.delete()
    }
    
    func cleanupAfterVNUploadCompleted(uploadObjectTrackerId: Int64) throws {
        guard let objectTracker = try UploadObjectTracker.fetchSingleRow(db: db, where: uploadObjectTrackerId == UploadObjectTracker.idField.description) else {
            throw SyncServerError.internalError("Problem in fetchSingleRow for UploadObjectTracker")
        }
        
        let fileTrackers = try objectTracker.dependentFileTrackers()
        try deleteTrackers(fileTrackers: fileTrackers, objectTracker: objectTracker)
    }
}
