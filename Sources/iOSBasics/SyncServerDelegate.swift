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

// These methods are all called on the `delegateDispatchQueue` passed to the SyncServer constructor.
public protocol SyncServerDelegate: AnyObject {
    func error(_ syncServer: SyncServer, error: Error?)
    
    // Called after the `sync` method is successful, and a nil sharingGroupUUID was given.
    func syncCompleted(_ syncServer: SyncServer)
    
    // After the `sync` method is successful, if a sharingGroupUUID was given, this gives the resulting file index for that sharing group.
    func syncCompleted(_ syncServer: SyncServer, sharingGroupUUID: UUID, index: [FileInfo])
    
    func downloadCompleted(_ syncServer: SyncServer, declObjectId: UUID)
    
    // A uuid that was initially generated on the client 
    func uuidCollision(_ syncServer: SyncServer, type: UUIDCollisionType, from: UUID, to: UUID)
    
    // The rest have informative detail; perhaps purely for testing.
    
    // The `queue` method was called, but the upload couldn't be done immediately. It was queued for upload later instead.
    func uploadQueued(_ syncServer: SyncServer, declObjectId: UUID)

    // Upload started successfully. Request was sent to server.
    func uploadStarted(_ syncServer: SyncServer, deferredUploadId:Int64)
    
    // Request to server for upload completed successfully.
    func uploadCompleted(_ syncServer: SyncServer, result: UploadFileResult)
    
    // Called when vN deferred upload(s), successfully completed, is/are detected.
    func deferredUploadsCompleted(_ syncServer: SyncServer, numberCompleted: Int)
}
