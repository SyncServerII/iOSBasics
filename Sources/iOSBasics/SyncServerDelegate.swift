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

public enum DownloadDeletion {
    case file(UUID)
    case fileGroup(UUID)
}

// These methods are all called on the `delegateDispatchQueue` passed to the SyncServer constructor.
public protocol SyncServerDelegate: AnyObject {
    func error(_ syncServer: SyncServer, error: Error?)
    
    // Called after the `sync` method is successful. If nil sharing group was given, the result is .noResult. If non-nil sharing group, the index is given.
    func syncCompleted(_ syncServer: SyncServer, result: SyncResult)
    
    func downloadCompleted(_ syncServer: SyncServer, declObjectId: UUID)
    
    // A uuid that was initially generated on the client 
    func uuidCollision(_ syncServer: SyncServer, type: UUIDCollisionType, from: UUID, to: UUID)
    
    // The rest have informative detail; perhaps purely for testing.
    
    // The `queue` method was called, but the upload couldn't be done immediately. It was queued for upload later instead.
    func uploadQueued(_ syncServer: SyncServer, declObjectId: UUID)

    // Upload started successfully. Request was sent to server.
    #warning("Get rid of deferredUploadId-- leaking internal ids.")
    func uploadStarted(_ syncServer: SyncServer, deferredUploadId:Int64)
    
    // Request to server for an upload completed successfully.
    func uploadCompleted(_ syncServer: SyncServer, result: UploadResult)
    
    // Called when vN deferred upload(s), or deferred deletions, successfully completed, is/are detected.
    func deferredCompleted(_ syncServer: SyncServer, operation: DeferredOperation, numberCompleted: Int)

    // Request to server for upload deletion completed successfully.
    func deletionCompleted(_ syncServer: SyncServer)
    
    // Another client deleted a file/file group.
    func downloadDeletion(_ syncServer: SyncServer, details: DownloadDeletion)
}


