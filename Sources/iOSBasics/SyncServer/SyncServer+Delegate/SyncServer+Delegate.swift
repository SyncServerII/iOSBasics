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
        block.sync {
            uploadCompletedHelper(delegated, result: result)
        }
    }
    
    func downloadCompleted(_ delegated: AnyObject, result: Swift.Result<DownloadFileResult, Error>) {
        block.sync {
            downloadCompletedHelper(delegated, result: result)
        }
    }
}
