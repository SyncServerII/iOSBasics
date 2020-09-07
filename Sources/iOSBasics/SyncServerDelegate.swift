import Foundation
import iOSSignIn

public enum UUIDCollisionType {
    case file
    case fileGroup
    case sharingGroup
    case device
}

public protocol SyncServerDelegate: AnyObject {
    func credentialsForServerRequests(_ syncServer: SyncServer) throws -> GenericCredentials
    
    func error(_ syncServer: SyncServer, error: Error?)
    
    func syncCompleted(_ syncServer: SyncServer)
    
    func downloadCompleted(_ syncServer: SyncServer, declObjectId: UUID)
    
    // A uuid that was initially generated on the client 
    func uuidCollision(_ syncServer: SyncServer, type: UUIDCollisionType, from: UUID, to: UUID)
    
    // Perhaps just for testing.
    
    // The `queue` method was called, but the upload couldn't be done immediately. It was queued for upload later instead.
    func uploadQueued(_ syncServer: SyncServer, declObjectId: UUID)

    // Upload started successfully. Request was sent to server.
    func uploadStarted(_ syncServer: SyncServer, deferredUploadId:Int64)
    
    // Request to server for upload completed successfully.
    func uploadCompleted(_ syncServer: SyncServer, result: UploadFileResult)
    
    func deferredUploadCompleted(_ syncServer: SyncServer)
}
