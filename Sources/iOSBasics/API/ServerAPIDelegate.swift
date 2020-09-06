import iOSSignIn
import Foundation
import iOSShared
import ServerShared

public enum UploadFileResult {
    public struct Upload {
        let fileUUID: UUID
        
        // Creation date is only returned when you upload a new file.
        let creationDate: Date?
        
        let updateDate: Date
        let uploadsFinished:UploadFileResponse.UploadsFinished
        let deferredUploadId: Int64?
    }
    
    case success(Upload)
        
    // The GoneReason should never be fileRemovedOrRenamed-- because a new upload would upload the next version, not accessing the current version.
    case gone(GoneReason)
}

public enum DownloadFileResult {
    case success(url: URL, appMetaData:AppMetaData?, checkSum:String, cloudStorageType:CloudStorageType, contentsChangedOnServer: Bool)
    
    // The GoneReason should never be userRemoved-- because when a user is removed, their files are marked as deleted in the FileIndex, and thus the files are generally not downloadable.
    case gone(appMetaData:AppMetaData?, cloudStorageType:CloudStorageType, GoneReason)
}

protocol ServerAPIDelegate: NetworkingDelegate {
    func hasher(_ delegated: AnyObject, forCloudStorageType cloudStorageType: CloudStorageType) throws -> CloudStorageHashing
    func error(_ delegated: AnyObject, error: Error?)
}
