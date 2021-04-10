import Foundation
import ServerShared
import iOSShared
import iOSSignIn
import SQLite
import Version

extension SyncServer: ServerAPIDelegate {
    func badVersion(_ delegated: AnyObject, version: BadVersion) {
        delegator { [weak self] delegate in
            guard let self = self else { return }
            delegate.badVersion(self, version: version)
        }
    }
    
    func networkingFailover(_ delegated: AnyObject, message: String) {
        delegator { [weak self] delegate in
            guard let self = self else { return }
            delegate.userEvent(self, event: .showAlert(title: "Alert!", message: message))
        }
    }

    func error(_ delegated: AnyObject, error: Error?) {
        delegator { [weak self] delegate in
            guard let self = self else { return }
            delegate.userEvent(self, event: .error(error))
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
    
    func uploadCompleted(_ delegated: AnyObject, file: Filenaming, result: Swift.Result<UploadFileResult, Error>) {
        uploadCompletedHelper(delegated, file: file, result: result)
    }
    
    func downloadCompleted(_ delegated: AnyObject, file: Filenaming, result: Swift.Result<DownloadFileResult, Error>) {
        downloadCompletedHelper(delegated, file: file, result: result)
    }
    
    func backgroundRequestCompleted(_ delegated: AnyObject, result: Swift.Result<BackgroundRequestResult, Error>) {
        backgroundRequestCompletedHelper(delegated, result: result)
    }
}
