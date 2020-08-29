import iOSSignIn
import Foundation
import iOSShared
import ServerShared

enum UploadFileResult {
    // Creation date is only returned when you upload a new file.
    case success(creationDate: Date?, updateDate: Date)
    
    case serverMasterVersionUpdate(Int64)
    
    // The GoneReason should never be fileRemovedOrRenamed-- because a new upload would upload the next version, not accessing the current version.
    case gone(GoneReason)
}

enum DownloadFileResult {
    case success(url: URL, appMetaData:AppMetaData?, checkSum:String, cloudStorageType:CloudStorageType, contentsChangedOnServer: Bool)
    case serverMasterVersionUpdate(Int64)
    
    // The GoneReason should never be userRemoved-- because when a user is removed, their files are marked as deleted in the FileIndex, and thus the files are generally not downloadable.
    case gone(appMetaData:AppMetaData?, cloudStorageType:CloudStorageType, GoneReason)
}
    
protocol ServerAPIDelegate: AnyObject {
    // Methods for the ServerAPI to get information from its user/caller
    func credentialsForNetworkRequests(_ api: AnyObject) -> GenericCredentials
    func deviceUUID(_ api: AnyObject) -> UUID
    func hasher(_ api: AnyObject, forCloudStorageType cloudStorageType: CloudStorageType) throws -> CloudStorageHashing
    
    // Methods for the ServerAPI to report results
    func uploadCompleted(_ api: AnyObject, result: Swift.Result<UploadFileResult, Error>)
    func downloadCompleted(_ api: AnyObject, result: Swift.Result<DownloadFileResult, Error>)
}
