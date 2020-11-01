
import Foundation
import iOSShared
import SQLite
import ServerShared

extension SyncServer {
    func uploadCompletedHelper(_ delegated: AnyObject, file: Filenaming, result: Swift.Result<UploadFileResult, Error>) {
        logger.debug("uploadCompleted: \(result)")
        
        guard let fileUUIDString = file.fileUUID,
            let fileUUID = UUID(uuidString: fileUUIDString) else {
            delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.error(self, error: .error(SyncServerError.internalError("Bad UUID")))
            }
            return
        }

        switch result {
        case .failure(let error):
            reportUploadError(fileUUID: fileUUID, trackerId: file.trackerId, error: error)
            
        case .success(let uploadFileResult):
            switch uploadFileResult {
            case .gone(_):
                do {
                    try cleanupAfterUploadCompleted(fileUUID: fileUUID, uploadObjectTrackerId: file.trackerId, result: nil)
                } catch let error {
                    reportUploadError(fileUUID: fileUUID, trackerId: file.trackerId, error: error)
                    return
                }
                
                goneDeleted(fileUUID: fileUUID)
                
                delegator { [weak self] delegate in
                    guard let self = self else { return }
                    let result = UploadResult(fileUUID: fileUUID, uploadType: .gone)
                    delegate.uploadQueue(self, event: .completed(result))
                }
                
            case .success(let uploadResult):
                do {
                    try cleanupAfterUploadCompleted(fileUUID: fileUUID, uploadObjectTrackerId: file.trackerId,  result: uploadResult)
                } catch let error {
                    reportUploadError(fileUUID: fileUUID, trackerId: file.trackerId, error: error)
                    return
                }

                // Waiting until now to mark a file as v0 if it is it's first upload-- so if earlier we have to retry a failed upload we remember to upload as v0.
                do {
                    guard let entry = try DirectoryFileEntry.fetchSingleRow(db: db, where:
                        fileUUID == DirectoryFileEntry.fileUUIDField.description) else {
                        reportUploadError(fileUUID: fileUUID, trackerId: file.trackerId, error: SyncServerError.internalError("Could not find DirectoryEntry"))
                        return
                    }
                    
                    if entry.fileVersion == nil {
                        try entry.update(setters:
                            DirectoryFileEntry.fileVersionField.description <- 0)
                    }
                    
                } catch let error {
                    reportUploadError(fileUUID: fileUUID, trackerId: file.trackerId, error: error)
                    return
                }
                
                delegator { [weak self] delegate in
                    guard let self = self else { return }
                    let result = UploadResult(fileUUID: fileUUID, uploadType: .success)
                    delegate.uploadQueue(self, event: .completed(result))
                }
            }
        }
    }

    private func reportUploadError(fileUUID: UUID, trackerId: Int64, error: Error) {
        delegator { [weak self] delegate in
            guard let self = self else { return }
            delegate.error(self, error: .error(error))
        }
        
        do {
            guard let fileTracker = try UploadFileTracker.fetchSingleRow(db: db, where: fileUUID == UploadFileTracker.fileUUIDField.description &&
                trackerId == UploadFileTracker.uploadObjectTrackerIdField.description) else {
                throw SyncServerError.internalError("Failed getting file tracker")
            }
            
            try fileTracker.update(setters:
                UploadFileTracker.statusField.description <- .notStarted)
        } catch let error {
            delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.error(self, error: .error(error))
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
                        delegate.error(self, error: .error(error))
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
                        delegate.error(self, error: .error(error))
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
                delegate.error(self, error: .error(error))
            }
        }
    }
    
/*
    // While a background request is a general method, we're actually only using them for upload deletions so far.
    func backgroundRequestCompletedHelper(_ delegated: AnyObject, result: Swift.Result<BackgroundRequestResult, Error>) {

        switch result {
        case .success(let requestResult):
            switch requestResult {
            case .success(objectTrackerId: _, let successResult):
                guard let requestInfo = successResult.requestInfo else {
                    deletionError(SyncServerError.internalError("No request info"), tracker: nil)
                    return
                }
    
                var tracker:UploadDeletionTracker!
                
                do {
                    let info = try JSONDecoder().decode(ServerAPI.DeletionRequestInfo.self, from: requestInfo)
                    
                    // Upload deletions are only using `fileGroupUUID` type so far.
                    guard info.uuidType == .fileGroupUUID else {
                        deletionError(SyncServerError.internalError("uuidType not fileGroupUUID as expected"), tracker: nil)
                        return
                    }
                    
                    tracker = try UploadDeletionTracker.fetchSingleRow(db: db, where: UploadDeletionTracker.uuidField.description == info.uuid)
                    
                    guard tracker != nil else {
                        deletionError(SyncServerError.internalError("Could not find UploadDeletionTracker"), tracker: nil)
                        return
                    }
                    
                    guard tracker.deletionType == .fileGroupUUID else {
                        deletionError(SyncServerError.internalError("UploadDeletionTracker did not have expected fileGroupUUID type"), tracker: tracker)
                        return
                    }
                    
                    let data = try Data(contentsOf: successResult.serverResponse)
                    try FileManager.default.removeItem(at: successResult.serverResponse)
                    let json = try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions(rawValue: UInt(0)))
                            
                    guard let jsonDict = json as? [String: Any] else {
                        deletionError(SyncServerError.internalError("Could not convert background request result to a dictionary"), tracker: tracker)
                        return
                    }
                            
                    let response = try UploadDeletionResponse.decode(jsonDict)
                    if let deferredUploadId = response.deferredUploadId {
                        try tracker.update(setters: UploadDeletionTracker.deferredUploadIdField.description <- deferredUploadId)
                        completeInitialDeletion(tracker: tracker, deferredUploadId: deferredUploadId)
                    }
                    else {
                        #warning("Can the server endpoint be changed so that on a second call it (at least sometimes) can send back the deferredUploadId?")
                        completeInitialDeletion(tracker: tracker, deferredUploadId: nil)
                    }
                } catch let error {
                    deletionError(error, tracker: tracker)
                }
                
            case .gone(objectTrackerId: let trackerId):
                // Since we're using this for a upload deletion, this also amounts to a certain kind of success. But, not going to wait for a deferred deletion here.
                do {
                    guard let tracker = try UploadDeletionTracker.fetchSingleRow(db: db, where: UploadDeletionTracker.idField.description == trackerId) else {
                        deletionError(SyncServerError.internalError("Could not find UploadDeletionTracker"), tracker: nil)
                        return
                    }
                    
                    self.completeInitialDeletion(tracker: tracker, deferredUploadId: nil)

                } catch let error {
                    deletionError(error, tracker: nil)
                }
            }
            
        case .failure(let error):
            deletionError(error, tracker: nil)
        }
    }
    
    private func deletionError(_ error: Error, tracker: UploadDeletionTracker?) {
        reportError(error)
        
        guard let tracker = tracker else {
            return
        }
        
        do {
            try tracker.update(setters:
            UploadDeletionTracker.statusField.description <- .notStarted)
        } catch let error {
            reportError(error)
        }
    }
*/
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
    
    // Called when an upload or download detects that a file is `gone`.
    private func goneDeleted(fileUUID: UUID) {
        do {
            guard let entry = try DirectoryFileEntry.fetchSingleRow(db: db, where:
                fileUUID == DirectoryFileEntry.fileUUIDField.description) else {
                delegator { [weak self] delegate in
                    guard let self = self else { return }
                    delegate.error(self, error: .error(SyncServerError.internalError("Could not find DirectoryFileEntry")))
                }
                return
            }
            
            // Specifically *not* changing `deletedLocallyField` because the difference between these two (i.e., deletedLocally false, and deletedOnServer true) will be used to drive local deletion for the client.
            try entry.update(setters:
                DirectoryFileEntry.deletedOnServerField.description <- true)

            delegator { [weak self] delegate in
                guard let self = self else { return }
                // Calling `downloadDeletion` here because an upload or a download has detected a file is gone. Actually, now that I think of it, whether or not the file is really `deleted` depends on the GoneReason. For example, for a GoneReason of `authTokenExpiredOrRevoked`, this should not be reported as a `downloadDeletion`.
                #warning("Need to get that reason and change this.")
                delegate.downloadDeletion(self, details: .file(fileUUID))
            }
            
        } catch let error {
            delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.error(self, error: .error(error))
            }
        }
    }
}
