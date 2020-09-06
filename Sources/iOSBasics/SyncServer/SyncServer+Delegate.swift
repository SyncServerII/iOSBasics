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

        switch result {
        case .failure(let error):
            delegate.error(self, error: error)
            
        case .success(let uploadFileResult):
            var fileUUID: UUID!
            
            switch uploadFileResult {
            case .gone:
                // TODO: Need the file uuid here too.
                break
                
            case .success(let uploadResult):
                fileUUID = uploadResult.fileUUID
            }
            
            do {
                if let uploadFileTracker = try UploadFileTracker.fetchSingleRow(db: db, where: fileUUID == UploadFileTracker.fileUUIDField.description),
                    let url = uploadFileTracker.localURL {
                    if uploadFileTracker.uploadCopy {
                        try FileManager.default.removeItem(at: url)
                    }
                    try uploadFileTracker.delete()
                }
                else {
                    delegate.error(self, error: SyncServerError.internalError("Problem removing UploadFileTracker"))
                }
            } catch let error {
                delegate.error(self, error: error)
            }
        
            delegate.uploadCompleted(self, result: uploadFileResult)
        }
    }
    
    func downloadCompleted(_ delegated: AnyObject, result: Swift.Result<DownloadFileResult, Error>) {
        assert(false)
    }
}
