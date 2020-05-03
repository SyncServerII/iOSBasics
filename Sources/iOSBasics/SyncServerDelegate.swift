import Foundation

public enum CollisionType {
    case file
    case fileGroup
    case sharingGroup
}

public protocol SyncServerDelegate: class {
    func syncCompleted(_ syncServer: SyncServer)
    
    // Called after a download started by a call to `startDownload` completes.
    func downloadCompleted(_ syncServer: SyncServer)
    
    // A uuid that was initially generated on the client 
    func uuidCollision(_ syncServer: SyncServer, type: CollisionType, from: UUID, to: UUID)
}
