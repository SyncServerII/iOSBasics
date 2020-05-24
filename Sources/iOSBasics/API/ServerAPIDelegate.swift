import iOSSignIn
import Foundation
import iOSShared
import ServerShared

enum UploadFileResult {
    case success(creationDate: Date, updateDate: Date)
    case serverMasterVersionUpdate(Int64)
    
    // The GoneReason should never be fileRemovedOrRenamed-- because a new upload would upload the next version, not accessing the current version.
    case gone(GoneReason)
}
    
protocol ServerAPIDelegate: AnyObject {
    // Methods for the ServerAPI to get information from its user/caller
    func credentialsForNetworkRequests(_ api: AnyObject) -> GenericCredentials
    func deviceUUID(_ api: AnyObject) -> UUID
    func currentHasher(_ api: AnyObject) -> CloudStorageHashing
    
    // Methods for the ServerAPI to report results
    func uploadCompleted(_ api: AnyObject, result: Swift.Result<UploadFileResult, Error>)
    func uploadError(_ api: AnyObject, error: Error)
    
    func downloadCompleted(_ api: AnyObject, result: Swift.Result<UploadFileResult, Error>)
    func downloadError(_ api: AnyObject, error: Error)
}
