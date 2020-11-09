
import Foundation
@testable import iOSBasics
import iOSSignIn
import XCTest
import iOSShared

class DelegateHandlers {
    class Extras {
        init() {}
        var uploadQueued:((SyncServer) -> ())?
        var uploadCompleted:((SyncServer, UploadResult) -> ())?
        var uploadStarted:((SyncServer) -> ())?
         
        var downloadQueued:((SyncServer) -> ())?
        var downloadCompleted:((SyncServer, DownloadResult) -> ())?
        var downloadSync:((SyncServer, _ numberDownloadsStarted: UInt) -> ())?

    }
    let extras = Extras()
    
    class ServerAPIHandlers {
        var uploadCompletedHandler: ((_ result: Swift.Result<UploadFileResult, Error>) -> ())?
        var downloadCompletedHandler: ((_ result: Swift.Result<DownloadFileResult, Error>) -> ())?
        var backgroundRequestCompletedHandler: ((_ result: Swift.Result<BackgroundRequestResult, Error>) -> ())?
    }
    let api = ServerAPIHandlers()

    var user:TestUser!
    
    var error:((_ syncServer: SyncServer, _ error: ErrorEvent)->())?
    
    var objectType:((_ caller: AnyObject, _ appMetaData: String) -> String?)?
    
    var syncCompleted: ((SyncServer, SyncResult) -> ())?
    
    // Use extras.
    // var uploadQueue:((SyncServer, UploadEvent) -> ())?

    var deferredCompleted: ((SyncServer, DeferredOperation, _ numberCompleted: Int) -> ())?
        
    var deletionCompleted: ((SyncServer) -> ())?
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
    func error(_ syncServer: SyncServer, error: ErrorEvent) {
        XCTFail("\(String(describing: error))")
        handlers.error?(syncServer, error)
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
    
    // A uuid that was initially generated on the client
    func uuidCollision(_ syncServer: SyncServer, type: UUIDCollisionType, from: UUID, to: UUID) {
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
    
    func deferredCompleted(_ syncServer: SyncServer, operation: DeferredOperation, numberCompleted: Int) {
        logger.debug("handlers: deferredCompleted")
        handlers.deferredCompleted?(syncServer, operation, numberCompleted)
    }
    
    func deletionCompleted(_ syncServer: SyncServer) {
        logger.debug("handlers: deletionCompleted")
        handlers.deletionCompleted?(syncServer)
    }
    
    func downloadDeletion(_ syncServer: SyncServer, details: DownloadDeletion) {
        handlers.downloadDeletion?(syncServer, details)
    }
}
