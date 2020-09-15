
import Foundation
import iOSShared
import SQLite

extension SyncServer {
    func uploadCompletedHelper(_ delegated: AnyObject, result: Swift.Result<UploadFileResult, Error>) {
        logger.debug("uploadCompleted: \(result)")

        switch result {
        case .failure(let error):
            delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.error(self, error: error)
            }
            
        case .success(let uploadFileResult):
            switch uploadFileResult {
            case .gone(let fileUUID, let trackerId, _):
                do {
                    try cleanupAfterUploadCompleted(fileUUID: fileUUID, uploadObjectTrackerId: trackerId, result: nil)
                } catch let error {
                    delegator { [weak self] delegate in
                        guard let self = self else { return }
                        delegate.error(self, error: error)
                    }
                }
                
                do {
                    guard let entry = try DirectoryEntry.fetchSingleRow(db: db, where:
                        fileUUID == DirectoryEntry.fileUUIDField.description) else {
                        delegator { [weak self] delegate in
                            guard let self = self else { return }
                            delegate.error(self, error: SyncServerError.internalError("Could not find DirectoryEntry"))
                        }
                        return
                    }
                    
                    try entry.update(setters:
                        DirectoryEntry.deletedLocallyField.description <- true,
                        DirectoryEntry.deletedOnServerField.description <- true)
                    
                } catch let error {
                    delegator { [weak self] delegate in
                        guard let self = self else { return }
                        delegate.error(self, error: error)
                    }
                }
                
                delegator { [weak self] delegate in
                    guard let self = self else { return }
                    let result = UploadResult(fileUUID: fileUUID, uploadType: .gone)
                    delegate.uploadCompleted(self, result: result)
                }
                
            case .success(let trackerId, let uploadResult):
                do {
                    try cleanupAfterUploadCompleted(fileUUID: uploadResult.fileUUID, uploadObjectTrackerId: trackerId,  result: uploadResult)
                } catch let error {
                    delegator { [weak self] delegate in
                        guard let self = self else { return }
                        delegate.error(self, error: error)
                    }
                }

                // Waiting until now to mark a file as v0 if it is it's first upload-- so if earlier we have to retry a failed upload we remember to upload as v0.
                do {
                    guard let entry = try DirectoryEntry.fetchSingleRow(db: db, where:
                        uploadResult.fileUUID == DirectoryEntry.fileUUIDField.description) else {
                        delegator { [weak self] delegate in
                            guard let self = self else { return }
                            delegate.error(self, error: SyncServerError.internalError("Could not find DirectoryEntry"))
                        }
                        return
                    }
                    
                    if entry.fileVersion == nil {
                        try entry.update(setters:
                            DirectoryEntry.fileVersionField.description <- 0)
                    }
                    
                } catch let error {
                    delegator { [weak self] delegate in
                        guard let self = self else { return }
                        delegate.error(self, error: error)
                    }
                }
                
                delegator { [weak self] delegate in
                    guard let self = self else { return }
                    let result = UploadResult(fileUUID: uploadResult.fileUUID, uploadType: .success)
                    delegate.uploadCompleted(self, result: result)
                }
            }
        }
    }
    
    func downloadCompletedHelper(_ delegated: AnyObject, result: Swift.Result<DownloadFileResult, Error>) {
        switch result {
        case .success(let downloadResult):
            switch downloadResult {
            case .gone:
                assert(false)
            case .success:
                delegator { [weak self] delegate in
                    guard let self = self else { return }
                    delegate.downloadCompleted(self, declObjectId: UUID())
                }
            }
            break
        case .failure(let error):
            delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.error(self, error: error)
            }
        }
    }
}

extension SyncServer {
    // For v0 uploads: Only mark the upload as done for the file tracker. Wait until *all* files have been uploaded until cleanup.
    // For vN uploads: Wait until the deferred upload completion to cleanup.
    // For Gone-- result will be nil.
    func cleanupAfterUploadCompleted(fileUUID: UUID, uploadObjectTrackerId: Int64, result: UploadFileResult.Upload?) throws {

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

        if let result = result {
            guard let v0Upload = objectTracker.v0Upload else {
                throw SyncServerError.internalError("v0Upload not set in UploadObjectTracker")
            }
        
            if v0Upload {
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
        else {
            // Gone case: Just remove trackers when we get reports back from all of them.
            let fileTrackers = try objectTracker.dependentFileTrackers()
            let remainingUploads = fileTrackers.filter {$0.status != .uploaded}
            
            if remainingUploads.count == 0 {
                try deleteTrackers(fileTrackers: fileTrackers, objectTracker: objectTracker)
            }
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
