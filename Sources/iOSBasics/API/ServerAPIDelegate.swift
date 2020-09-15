import iOSSignIn
import Foundation
import iOSShared
import ServerShared

enum UploadFileResult {
    public struct Upload {
        let fileUUID: UUID
        
        // Creation date is only returned when you upload a new file.
        let creationDate: Date?
        
        let updateDate: Date
        let uploadsFinished:UploadFileResponse.UploadsFinished
        let deferredUploadId: Int64?
    }
    
    case success(uploadObjectTrackerId: Int64, Upload)
    
    case gone(fileUUID: UUID, uploadObjectTrackerId: Int64, GoneReason)
}

enum DownloadFileResult {
    case success(url: URL, appMetaData:AppMetaData?, checkSum:String, cloudStorageType:CloudStorageType, contentsChangedOnServer: Bool)
    
    // The GoneReason should never be userRemoved-- because when a user is removed, their files are marked as deleted in the FileIndex, and thus the files are generally not downloadable.
    case gone(appMetaData:AppMetaData?, cloudStorageType:CloudStorageType, GoneReason)
}

protocol ServerAPIDelegate: NetworkingDelegate {
    func hasher(_ delegated: AnyObject, forCloudStorageType cloudStorageType: CloudStorageType) throws -> CloudStorageHashing
    func error(_ delegated: AnyObject, error: Error?)
}
