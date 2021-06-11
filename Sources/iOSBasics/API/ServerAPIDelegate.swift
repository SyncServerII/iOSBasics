import iOSSignIn
import Foundation
import iOSShared
import ServerShared

enum UploadFileResult {
    public struct Upload {        
        // Creation date is only returned when you upload a new file.
        let creationDate: Date?
        
        let updateDate: Date
        let uploadsFinished:UploadFileResponse.UploadsFinished
        let deferredUploadId: Int64?
    }
    
    case success(Upload)
    
    case gone(GoneReason)
    case conflict(ConflictReason)
}

enum DownloadFileResult {
    public struct Download {
        let fileUUID: UUID
        let url: URL
        let checkSum:String
        let contentsChangedOnServer: Bool
        let appMetaData: String?
    }
    
    case success(objectTrackerId: Int64, Download)
    
    // The GoneReason should never be userRemoved-- because when a user is removed, their files are marked as deleted in the FileIndex, and thus the files are generally not downloadable.
    case gone(objectTrackerId: Int64, fileUUID: UUID, GoneReason)
}

enum BackgroundRequestResult {
    public struct SuccessResult {
        let serverResponse: URL
        let requestInfo: Data?
    }
    
    case success(objectTrackerId: Int64, SuccessResult)
    
    case gone(objectTrackerId: Int64)
}

protocol ServerAPIDelegate: NetworkingDelegate {
    func hasher(_ delegated: AnyObject, forCloudStorageType cloudStorageType: CloudStorageType) throws -> CloudStorageHashing
    func error(_ delegated: AnyObject, error: Error?)
}
