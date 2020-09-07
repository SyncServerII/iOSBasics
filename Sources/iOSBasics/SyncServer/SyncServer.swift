import Foundation
import SQLite
import iOSShared
import ServerShared
import iOSSignIn

// Calls SyncServerDelegate methods on the `delegateDispatchQueue` either synchronously or asynchronously.
class Delegator {
    private weak var delegate: SyncServerDelegate!
    private let delegateDispatchQueue: DispatchQueue
    
    init(delegate: SyncServerDelegate, delegateDispatchQueue: DispatchQueue) {
        self.delegate = delegate
        self.delegateDispatchQueue = delegateDispatchQueue
    }
    
    // All delegate methods must be called using this, to have them called on the client requested DispatchQueue. Delegate methods are called asynchronously on the `delegateDispatchQueue`.
    // (Not doing sync here becuase need to resolve issue: https://stackoverflow.com/questions/63784355)
    func call(callback: @escaping (SyncServerDelegate)->()) {
        /*
        if sync {
            // This is crashing with: Thread 1: EXC_BAD_INSTRUCTION (code=EXC_I386_INVOP, subcode=0x0)
            // seemingly because I am doing a sync dispatch on the main thread when I'm already on the main thread. The problem is, I can't compare threads/queues. https://stackoverflow.com/questions/17489098
            let isMainThread = Thread.isMainThread
            logger.debug("isMainThread: \(isMainThread)")
            delegateDispatchQueue.sync { [weak self] in
                guard let self = self else { return }
                callback(self.delegate)
            }
        }
        */
        delegateDispatchQueue.async { [weak self] in
            guard let self = self else { return }
            callback(self.delegate)
        }
    }
}

public class SyncServer {
    // This *must* be set by the caller/user of this class before use of methods of this class.
    public weak var delegate: SyncServerDelegate! {
        set {
            _delegator = Delegator(delegate: newValue, delegateDispatchQueue: delegateDispatchQueue)
        }
        
        // Don't use this getter internally. Use `delegator` to call delegate methods.
        get {
            assert(false)
            return nil
        }
    }
    
    // This *must* also be set by the caller/user of this class before use of methods of this class.
    public weak var credentialsDelegate: SyncServerCredentials!
    
    // Use these to call delegate methods.
    private(set) var _delegator: Delegator!
    func delegator(callDelegate: @escaping (SyncServerDelegate)->()) {
        _delegator.call(callback: callDelegate)
    }

    let configuration: Configuration
    let db: Connection
    var signIns: SignIns!
    let hashingManager: HashingManager
    private(set) var api:ServerAPI!
    let delegateDispatchQueue: DispatchQueue
    
    // `delegateDispatchQueue` is used to call `SyncServerDelegate` methods. (`SyncServerCredentials` methods may be called on any queue.)
    public init(hashingManager: HashingManager,
        db:Connection,
        configuration: Configuration,
        delegateDispatchQueue: DispatchQueue = DispatchQueue.main) throws {
        self.configuration = configuration
        self.db = db
        self.hashingManager = hashingManager
        self.delegateDispatchQueue = delegateDispatchQueue
        set(logLevel: .trace)
        
        try Database.setup(db: db)

        api = ServerAPI(database: db, hashingManager: hashingManager, delegate: self, config: configuration)
    }
    
    // MARK: Persistent queuing for upload
    
    // TODO: Get list of pending downloads, and if no conflicting uploads, do these uploads.
    // TODO: If there are conflicting uploads, the downloads will need to be manually started first (see methods below) and then sync retried.
    // Uploads are done on a background networking URLSession.
    // If you upload an object that has a fileGroupUUID which is already queued or in progress of uploading, your request will be queued.
    // The first time you queue a SyncedObject, this call persistently registers the DeclaredObject portion of the object. Subsequent `queue` calls with the same syncObjectId in the object, must exactly match the DeclaredObject.
    // The `uuid` of files present in the uploads must be in the declaration.
    public func queue<DECL: DeclarableObject, UPL:UploadableFile>
        (declaration: DECL, uploads: Set<UPL>) throws {
        try queueObject(declaration: declaration, uploads: uploads)
    }
    
    // Trigger any next pending uploads or downloads. In general, after a set of uploads or downloads have been triggered by your call(s) to SyncServer methods, further uploads or downloads are not automatically initiated. It's up to the caller of this interface to call `sync` periodically to drive that. It's likely best that `sync` only be called while the app is in the foreground-- to avoid penalties (e.g., increased latencies) incurred by initating network requests, from other networking requests, while the app is in the background. Uploads and downloads are carried out using a background URLSession and so can run while the app is in the background.
    // This also checks if vN deferred uploads server requests have completed.
    public func sync() throws {
        try triggerUploads()
        
        // `checkOnDeferredUploads` does networking calls *synchronously*. So run it asynchronously as to not block the caller for a long period of time.
        DispatchQueue.global().async {
            do {
                let count = try self.checkOnDeferredUploads()
                if count > 0 {
                    self.delegator { [weak self] delegate in
                        guard let self = self else { return }
                        delegate.deferredUploadsCompleted(self, numberCompleted: count)
                    }
                }
            } catch let error {
                self.delegator { [weak self] delegate in
                    guard let self = self else { return }
                    delegate.error(self, error: error)
                }
            }
        }
    }
    
    // MARK: Unqueued requests-- these will fail if they involve a file or other object currently queued for upload.
    
    public func uploadAppMetaData(file: UUID) {
    }
    
//    public func delete(object: SyncedObject) {
//    }
    
    public func createSharingGroup(sharingGroup: UUID, sharingGroupName: String? = nil) {
    }
    
    public func updateSharingGroup(sharingGroup: UUID, newSharingGroupName: String) {
    }
    
    // Remove the current user from the sharing group.
    public func removeFromSharingGroup(sharingGroup: UUID) {
    }
    
    // MARK: Download
    
    // The list of files returned here survive app relaunch.
    func filesNeedingDownload() -> [(UUID, FileVersionInt)] {
        return []
    }
    
    // This method is typically used to trigger downloads of files indicated in filesNeedingDownload, but it can also be used to trigger downloads independently of that.
    func startDownload(file: UUID, version: FileVersionInt) {
    }
    
    // MARK: Sharing
    
    public struct SharingGroup {
        let sharingGroup: UUID
        let sharingGroupName: String?
    }
    
    public var sharingGroups: [SharingGroup] {
        return []
    }
    
    public struct Permission {
    }
    
    public func createSharingInvitation(withPermission permission:Permission, sharingGroupUUID: String, numberAcceptors: UInt, allowSharingAcceptance: Bool = true, completion:((_ invitationCode:String?, Error?)->(Void))?) {
    }
    
    // MARK: Accessor
    
    public func getAttributes(forFileUUID fileUUID: UUID) {
    }
    
    // MARK: Reset
    
    public func reset() {
    
    }
    
    // MARK: Migration support.
    
    public func importFiles(files: [UUID]) {
    }
}

