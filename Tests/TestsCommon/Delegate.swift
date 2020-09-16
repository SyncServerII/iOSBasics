
import Foundation
@testable import iOSBasics
import iOSSignIn
import XCTest

class DelegateHandlers {
    var user:TestUser!
    
    var error:((SyncServer, Error?) -> ())?
    
    var syncCompleted: ((SyncServer, SyncResult) -> ())?
    
    var uploadQueued: ((SyncServer, _ syncObjectId: UUID) -> ())?
    var uploadStarted: ((SyncServer, _ deferredUploadId:Int64) -> ())?
    var uploadCompleted: ((SyncServer, UploadResult) -> ())?
    var deferredCompleted: ((SyncServer, DeferredOperation, _ numberCompleted: Int) -> ())?
        
    var deletionCompleted: ((SyncServer) -> ())?
    var downloadDeletion: ((SyncServer, DownloadDeletion) -> ())?
    var downloadCompleted: ((SyncServer, _ declObjectId: UUID) -> ())?
}

protocol Delegate: SyncServerDelegate, SyncServerCredentials {
    var handlers: DelegateHandlers { get }
}

extension Delegate  {
    func credentialsForServerRequests(_ syncServer: SyncServer) throws -> GenericCredentials {
        return handlers.user.credentials
    }
}

extension Delegate {
    func error(_ syncServer: SyncServer, error: Error?) {
        XCTFail("\(String(describing: error))")
        handlers.error?(syncServer, error)
    }

    func syncCompleted(_ syncServer: SyncServer, result: SyncResult) {
        handlers.syncCompleted?(syncServer, result)
    }
    
    func downloadCompleted(_ syncServer: SyncServer, declObjectId: UUID) {
        handlers.downloadCompleted?(syncServer, declObjectId)
    }
    
    // A uuid that was initially generated on the client
    func uuidCollision(_ syncServer: SyncServer, type: UUIDCollisionType, from: UUID, to: UUID) {
    }
    
    func uploadQueued(_ syncServer: SyncServer, declObjectId: UUID) {
        handlers.uploadQueued?(syncServer, declObjectId)
    }
    
    func uploadStarted(_ syncServer: SyncServer, deferredUploadId:Int64) {
        handlers.uploadStarted?(syncServer, deferredUploadId)
    }
    
    func uploadCompleted(_ syncServer: SyncServer, result: UploadResult) {
        handlers.uploadCompleted?(syncServer, result)
    }
    
    func deferredCompleted(_ syncServer: SyncServer, operation: DeferredOperation, numberCompleted: Int) {
        handlers.deferredCompleted?(syncServer, operation, numberCompleted)
    }
    
    func deletionCompleted(_ syncServer: SyncServer) {
        handlers.deletionCompleted?(syncServer)
    }
    
    func downloadDeletion(_ syncServer: SyncServer, details: DownloadDeletion) {
        handlers.downloadDeletion?(syncServer, details)
    }
}
