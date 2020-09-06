import iOSSignIn
import Foundation
import iOSShared
import ServerShared

public enum UploadFileResult {
    // Creation date is only returned when you upload a new file.
    case success(creationDate: Date?, updateDate: Date, uploadsFinished:UploadFileResponse.UploadsFinished, deferredUploadId: Int64?)
        
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
