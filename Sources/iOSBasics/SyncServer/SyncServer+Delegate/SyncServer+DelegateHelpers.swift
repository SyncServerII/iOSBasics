
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
                
                goneDeleted(fileUUID: fileUUID)
                
                delegator { [weak self] delegate in
                    guard let self = self else { return }
                    let result = UploadResult(fileUUID: fileUUID, uploadType: .gone)
                    delegate.uploadQueue(self, event: .completed(result))
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
                    delegate.uploadQueue(self, event: .completed(result))
                }
            }
        }
    }
    
    func downloadCompletedHelper(_ delegated: AnyObject, result: Swift.Result<DownloadFileResult, Error>) {
        switch result {
        case .success(let downloadResult):
            switch downloadResult {
            case .gone(let objectTrackerId, let fileUUID, _):
                do {
                    try cleanupAfterDownloadCompleted(fileUUID: fileUUID, objectTrackerId: objectTrackerId)
                } catch let error {
                    delegator { [weak self] delegate in
                        guard let self = self else { return }
                        delegate.error(self, error: error)
                    }
                }
                
                goneDeleted(fileUUID: fileUUID)
                
                delegator { [weak self] delegate in
                    guard let self = self else { return }
                    let result = DownloadResult(fileUUID: fileUUID, downloadType: .gone)
                    delegate.downloadQueue(self, event: .completed(result))
                }
                
            case .success(let objectTrackerId, let result):
                do {
                    try cleanupAfterDownloadCompleted(fileUUID: result.fileUUID, objectTrackerId: objectTrackerId)
                } catch let error {
                    delegator { [weak self] delegate in
                        guard let self = self else { return }
                        delegate.error(self, error: error)
                    }
                }
                
                delegator { [weak self] delegate in
                    guard let self = self else { return }
                    let result = DownloadResult(fileUUID: result.fileUUID, downloadType: .success(localFile: result.url))
                    delegate.downloadQueue(self, event: .completed(result))
                }
            }

        case .failure(let error):
            delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.error(self, error: error)
            }
        }
    }
    
    func backgroundRequestCompletedHelper(_ delegated: AnyObject, result: Swift.Result<BackgroundRequestResult, Error>) {
        assert(false)
        #warning("TODO")
    }
}

extension SyncServer {
    func deleteDownloadTrackers(fileTrackers: [DownloadFileTracker], objectTracker: DownloadObjectTracker) throws {
        for fileTracker in fileTrackers {
            try fileTracker.delete()
        }
        
        try objectTracker.delete()
    }
    
    func cleanupAfterDownloadCompleted(fileUUID:UUID, objectTrackerId: Int64) throws {
        // There can be more than one row in DownloadFileTracker with the same fileUUID here because we can queue the same download multiple times. Therefore, need to also search by objectTrackerId.
        guard let fileTracker = try DownloadFileTracker.fetchSingleRow(db: db, where: fileUUID == DownloadFileTracker.fileUUIDField.description &&
            objectTrackerId == DownloadFileTracker.downloadObjectTrackerIdField.description) else {
            throw SyncServerError.internalError("Problem in fetchSingleRow for DownloadFileTracker")
        }

        guard let objectTracker = try DownloadObjectTracker.fetchSingleRow(db: db, where: fileTracker.downloadObjectTrackerId  == DownloadObjectTracker.idField.description) else {
            throw SyncServerError.internalError("Problem in fetchSingleRow for DownloadObjectTracker")
        }

        try fileTracker.update(setters:
            DownloadFileTracker.statusField.description <- .downloaded)
            
        // Have all downloads successfully completed? If so, can delete all trackers, including those for files and the overall object.
        let fileTrackers = try objectTracker.dependentFileTrackers()
        let remainingUploads = fileTrackers.filter {$0.status != .downloaded}
        
        if remainingUploads.count == 0 {
            try deleteDownloadTrackers(fileTrackers: fileTrackers, objectTracker: objectTracker)
        }
    }
    
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
                    try deleteUploadTrackers(fileTrackers: fileTrackers, objectTracker: objectTracker)
                    
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
                try deleteUploadTrackers(fileTrackers: fileTrackers, objectTracker: objectTracker)
            }
            
            delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.downloadDeletion(self, details: .fileGroup(objectTracker.fileGroupUUID))
            }
        }
    }
    
    func deleteUploadTrackers(fileTrackers: [UploadFileTracker], objectTracker: UploadObjectTracker) throws {
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
        try deleteUploadTrackers(fileTrackers: fileTrackers, objectTracker: objectTracker)
    }
    
    func goneDeleted(fileUUID: UUID) {
        do {
            guard let entry = try DirectoryEntry.fetchSingleRow(db: db, where:
                fileUUID == DirectoryEntry.fileUUIDField.description) else {
                delegator { [weak self] delegate in
                    guard let self = self else { return }
                    delegate.error(self, error: SyncServerError.internalError("Could not find DirectoryEntry"))
                }
                return
            }
            
            // Specifically *not* changing `deletedLocallyField` because the difference between these two (i.e., deletedLocally false, and deletedOnServer true) will be used to drive local deletion for the client.
            try entry.update(setters:
                DirectoryEntry.deletedOnServerField.description <- true)

            delegator { [weak self] delegate in
                guard let self = self else { return }
                #warning("Not sure why I have this as downloadDeletion here.")
                delegate.downloadDeletion(self, details: .file(fileUUID))
            }
            
        } catch let error {
            delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.error(self, error: error)
            }
        }
    }
}
