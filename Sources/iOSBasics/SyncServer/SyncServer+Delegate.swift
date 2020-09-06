//
//  File.swift
//  
//
//  Created by Christopher G Prince on 9/6/20.
//

import Foundation
import ServerShared
import iOSShared
import iOSSignIn
import SQLite

extension SyncServer: ServerAPIDelegate {
    func error(_ delegated: AnyObject, error: Error?) {
        delegate.error(self, error: error)
    }
    
    func hasher(_ delegated: AnyObject, forCloudStorageType cloudStorageType: CloudStorageType) throws -> CloudStorageHashing {
        return try hashingManager.hashFor(cloudStorageType: cloudStorageType)
    }
    
    func credentialsForNetworkRequests(_ delegated: AnyObject) throws -> GenericCredentials {
        return try delegate.credentialsForServerRequests(self)
    }
    
    func deviceUUID(_ delegated: AnyObject) -> UUID {
        return configuration.deviceUUID
    }
    
    func uploadCompleted(_ delegated: AnyObject, result: Swift.Result<UploadFileResult, Error>) {
        logger.debug("uploadCompleted: \(result)")

        switch result {
        case .failure(let error):
            delegate.error(self, error: error)
            
        case .success(let uploadFileResult):
            switch uploadFileResult {
            case .gone:
                // TODO: Need the file uuid here too. And the uploadObjectTrackerId.
                break
                
            case .success(let trackerId, let uploadResult):
                do {
                    try cleanupAfterUploadCompleted(uploadObjectTrackerId: trackerId, fileUUID: uploadResult.fileUUID, result: uploadResult)
                } catch let error {
                    delegate.error(self, error: error)
                }
                
                delegate.uploadCompleted(self, result: uploadFileResult)
            }
        }
    }
    
    func downloadCompleted(_ delegated: AnyObject, result: Swift.Result<DownloadFileResult, Error>) {
        assert(false)
    }
}

extension SyncServer {
    func cleanupAfterUploadCompleted(uploadObjectTrackerId: Int64, fileUUID: UUID, result: UploadFileResult.Upload) throws {
    
        // There can be more than one row in UploadFileTracker with the same fileUUID here because we can queue the same upload multiple times. Therefore, need to also search by uploadObjectTrackerId.
        guard let uploadFileTracker = try UploadFileTracker.fetchSingleRow(db: db, where: fileUUID == UploadFileTracker.fileUUIDField.description &&
            uploadObjectTrackerId == UploadFileTracker.uploadObjectTrackerIdField.description),
            let url = uploadFileTracker.localURL else {
            throw SyncServerError.internalError("Problem in fetchSingleRow for UploadFileTracker")
        }
        
        if uploadFileTracker.uploadCopy {
            try FileManager.default.removeItem(at: url)
        }
        try uploadFileTracker.delete()
        
        // Are there other UploadFileTracker's for this uploadObjectTrackerId?
        // If not, should remove the UploadObjectTracker.
        let remainingTrackers = try UploadFileTracker.fetch(db: db, where: uploadObjectTrackerId == UploadFileTracker.uploadObjectTrackerIdField.description)
        if remainingTrackers.count == 0 {
            try UploadObjectTracker.delete(rowId: uploadObjectTrackerId, db: db)
            
            // Once we start doing vN uploads, expect this to fail.
            guard result.uploadsFinished == .v0UploadsFinished else {
                throw SyncServerError.internalError("Did not get v0UploadsFinished when expected.")
            }
        }
    }
}
