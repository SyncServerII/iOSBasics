import Foundation

public enum UUIDCollisionType {
    case file
    case fileGroup
    case sharingGroup
    case device
}

public protocol SyncServerDelegate: AnyObject {
    func syncCompleted(_ syncServer: SyncServer)
    
    func downloadCompleted(_ syncServer: SyncServer, syncObjectId: UUID)
    
    // A uuid that was initially generated on the client 
    func uuidCollision(_ syncServer: SyncServer, type: UUIDCollisionType, from: UUID, to: UUID)
}
