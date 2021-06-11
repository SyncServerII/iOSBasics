
import Foundation
@testable import iOSBasics
import iOSSignIn
import XCTest
import iOSShared
import Version

class DelegateHandlers {
    class Extras {
        init() {}
        var uploadQueued:((SyncServer) -> ())?
        var uploadCompleted:((SyncServer, UploadResult) -> ())?
        var uploadStarted:((SyncServer) -> ())?
         
        var downloadQueued:((SyncServer) -> ())?
        var downloadCompleted:((SyncServer, DownloadResult) -> ())?
        var objectMarked:((SyncServer, DownloadState, _ fileGroupUUID: UUID)->())?
        var downloadSync:((SyncServer, _ numberDownloadsStarted: UInt) -> ())?
    }
    let extras = Extras()
    
    class ServerAPIHandlers {
        var uploadCompletedHandler: ((_ result: Swift.Result<UploadFileResult, Error>) -> ())?
        var downloadCompletedHandler: ((_ result: Swift.Result<DownloadFileResult, Error>, _ file: Filenaming) -> ())?
        var backgroundRequestCompletedHandler: ((_ result: Swift.Result<BackgroundRequestResult, Error>) -> ())?
        var badVersion: ((_ delegated: AnyObject, _ version: BadVersion) -> ())?
    }
    let api = ServerAPIHandlers()

    var user:TestUser!
    
    var userEvent:((_ syncServer: SyncServer, _ event: UserEvent)->())?
    
    var objectType:((_ caller: AnyObject, _ appMetaData: String) -> String?)?
    
    var syncCompleted: ((SyncServer, SyncResult) -> ())?
    
    var uuidCollision: ((SyncServer, UUIDCollisionType, _ from: UUID, _ to: UUID) -> ())?
    
    // Use extras.
    // var uploadQueue:((SyncServer, UploadEvent) -> ())?

    var deferredCompleted: ((SyncServer, DeferredOperation, _ fileGroupUUIDs: [UUID]) -> ())?
        
    var deletionCompleted: ((SyncServer, _ fileGroupUUID: UUID) -> ())?
    var downloadDeletion: ((SyncServer, DownloadDeletion) -> ())?
    
    // Use Extras
    // var downloadQueue: ((SyncServer, DownloadEvent) -> ())?
}

protocol Delegate: SyncServerDelegate, SyncServerCredentials, SyncServerHelpers {
    var handlers: DelegateHandlers { get }
}

extension Delegate  {
    func credentialsForServerRequests(_ syncServer: SyncServer) throws -> GenericCredentials {
        return handlers.user.credentials
    }
}

extension Delegate {
    func badVersion(_ syncServer: SyncServer, version: BadVersion) {
        XCTFail()
    }
    
    func userEvent(_ syncServer: SyncServer, event: UserEvent){
        XCTFail("\(String(describing: event))")
        handlers.userEvent?(syncServer, event)
    }
    
    func objectType(_ caller: AnyObject, forAppMetaData appMetaData: String) -> String? {
        return handlers.objectType?(caller, appMetaData)
    }

    func syncCompleted(_ syncServer: SyncServer, result: SyncResult) {
        handlers.syncCompleted?(syncServer, result)
    }
    
    func downloadQueue(_ syncServer: SyncServer, event: DownloadEvent) {
        switch event {
        case .queued:
            handlers.extras.downloadQueued?(syncServer)
        case .completed(let result):
            handlers.extras.downloadCompleted?(syncServer, result)
        case .sync(let numberDownloadsStarted):
            handlers.extras.downloadSync?(syncServer, numberDownloadsStarted)
        }
    }
    
    func objectMarked(_ syncServer: SyncServer, withDownloadState state: DownloadState, fileGroupUUID: UUID) {
        handlers.extras.objectMarked?(syncServer, state, fileGroupUUID)
    }
    
    // A uuid that was initially generated on the client
    func uuidCollision(_ syncServer: SyncServer, type: UUIDCollisionType, from: UUID, to: UUID) {
        handlers.uuidCollision?(syncServer, type, from, to)
    }
    
    func uploadQueue(_ syncServer: SyncServer, event: UploadEvent) {
        switch event {
        case .queued:
            handlers.extras.uploadQueued?(syncServer)
            
        case .started:
            handlers.extras.uploadStarted?(syncServer)
            
        case .completed(let result):
            handlers.extras.uploadCompleted?(syncServer, result)
        }
    }
    
    func deferredCompleted(_ syncServer: SyncServer, operation: DeferredOperation, fileGroupUUIDs: [UUID]) {
        logger.debug("handlers: deferredCompleted")
        handlers.deferredCompleted?(syncServer, operation, fileGroupUUIDs)
    }
    
    func deletionCompleted(_ syncServer: SyncServer, forObjectWith fileGroupUUID: UUID) {
        logger.debug("handlers: deletionCompleted")
        handlers.deletionCompleted?(syncServer, fileGroupUUID)
    }
    
    func downloadDeletion(_ syncServer: SyncServer, details: DownloadDeletion) {
        handlers.downloadDeletion?(syncServer, details)
    }
}
