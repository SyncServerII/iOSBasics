import Foundation
import iOSSignIn
import ServerShared

public enum UUIDCollisionType {
    case file
    case fileGroup
    case sharingGroup
    case device
}

public protocol SyncServerCredentials: AnyObject {
    // This method may be called using *any* queue.
    func credentialsForServerRequests(_ syncServer: SyncServer) throws -> GenericCredentials
}

public enum SyncResult {
    case noIndex
    case index(sharingGroupUUID: UUID, index: [FileInfo])
}

public enum DeferredOperation {
    case upload
    case deletion
}

public struct UploadResult {
    public enum UploadType {
        case gone
        case success
    }
    
    let fileUUID: UUID
    let uploadType: UploadType
    
    public init(fileUUID: UUID, uploadType: UploadType) {
        self.fileUUID = fileUUID
        self.uploadType = uploadType
    }
}

public struct DownloadResult {
    public enum DownloadType {
        case gone
        case success(localFile: URL)
    }
    
    let fileUUID: UUID
    let downloadType: DownloadType
    
    public init(fileUUID: UUID, downloadType: DownloadType) {
        self.fileUUID = fileUUID
        self.downloadType = downloadType
    }
}

public enum DownloadDeletion {
    case file(UUID)
    case fileGroup(UUID)
}

public enum DownloadEvent {
    // The `queue` method was called, but the download couldn't be done immediately. It was queued for download later instead.
    case queued(fileGroupUUID: UUID)
    
    case completed(DownloadResult)
}

public enum UploadEvent {
    // The `queue` method was called, but the upload couldn't be done immediately. It was queued for upload later instead.
    case queued(fileGroupUUID: UUID)
    
    // Upload started successfully. Request was sent to server.
    case started
    
    // Request to server for an upload completed successfully.
    case completed(UploadResult)
}

// These methods are all called on the `delegateDispatchQueue` passed to the SyncServer constructor.
public protocol SyncServerDelegate: AnyObject {
    func error(_ syncServer: SyncServer, error: Error?)
    
    // Called after the `sync` method is successful. If nil sharing group was given, the result is .noResult. If non-nil sharing group, the index is given.
    func syncCompleted(_ syncServer: SyncServer, result: SyncResult)

    // A uuid that was initially generated on the client 
    func uuidCollision(_ syncServer: SyncServer, type: UUIDCollisionType, from: UUID, to: UUID)
    
    // The rest have informative detail; perhaps purely for testing.
    
    func uploadQueue(_ syncServer: SyncServer, event: UploadEvent)
    func downloadQueue(_ syncServer: SyncServer, event: DownloadEvent)

    // Called when vN deferred upload(s), or deferred deletions, successfully completed, is/are detected.
    func deferredCompleted(_ syncServer: SyncServer, operation: DeferredOperation, numberCompleted: Int)

    // Request to server for upload deletion completed successfully.
    func deletionCompleted(_ syncServer: SyncServer)
    
    // Another client deleted a file/file group.
    func downloadDeletion(_ syncServer: SyncServer, details: DownloadDeletion)
}


