import Foundation

public enum CollisionType {
    case file
    case fileGroup
    case sharingGroup
}

public protocol SyncServerDelegate: class {
    func syncCompleted(_ syncServer: SyncServer)
    
    func downloadCompleted(_ syncServer: SyncServer, object: SyncedObject)
    
    // A uuid that was initially generated on the client 
    func uuidCollision(_ syncServer: SyncServer, type: CollisionType, from: UUID, to: UUID)
}
