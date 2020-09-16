import Foundation
import SQLite
import iOSShared
import ServerShared
import iOSSignIn

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
    private var _delegator: Delegator!
    func delegator(callDelegate: @escaping (SyncServerDelegate)->()) {
        _delegator.call(callback: callDelegate)
    }

    let configuration: Configuration
    let db: Connection
    var signIns: SignIns!
    let hashingManager: HashingManager
    private(set) var api:ServerAPI!
    let delegateDispatchQueue: DispatchQueue
    var _sharingGroups = [ServerShared.SharingGroup]()

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
    
    // If you upload an object that has a fileGroupUUID which is already queued or in progress of uploading, your request will be queued.
    // The first time you queue a SyncedObject, this call persistently registers the DeclaredObject portion of the object. Subsequent `queue` calls with the same syncObjectId in the object, must exactly match the DeclaredObject.
    // The `uuid` of files present in the uploads must be in the declaration.
    // All files that end up being uploaded in the same queued batch must either be v0 (their first upload) or vN (not their first upload). It is an error to attempt to upload v0 and vN files together in the same batch. This issue may not always be detected (i.e., an error thrown by this call). An error might instead be thrown on a subsequent call to `sync`.
    // In this last regard, it is a best practice to do a v0 upload for all files in a declared object in it's first `queue` call. This way, having both v0 and vN files in the same queued batch *cannot* occur.
    // Uploads are done on a background networking URLSession.
    public func queueUploads<DECL: DeclarableObject, UPL:UploadableFile>
        (declaration: DECL, uploads: Set<UPL>) throws {
        try queueObject(declaration: declaration, uploads: uploads)
    }
    
    /* This performs a variety of actions:
    1) It triggers any next pending uploads. In general, after a set of uploads queued by your call(s) to the SyncServer `queueUploads` method, further uploads are not automatically initiated. It's up to the caller of this interface to call `sync` periodically to drive that. It's likely best that `sync` only be called while the app is in the foreground-- to avoid penalties (e.g., increased latencies) incurred by initating network requests, from other networking requests, while the app is in the background. Uploads are carried out using a background URLSession and so can run while the app is in the background.
    2) It checks if vN deferred uploads server requests have completed.
    3) If a non-nil sharingGroupUUID is given, this fetches the index for all files in that sharing group from the server. If successful, the syncCompleted delegate method is called, and:
        a) the `sharingGroups` property has been updated
        b) the `filesNeedingDownload` method can be called to determine any files needing downloading for the sharing group.
    4) If a nil sharingGroupUUID is given, this fetches all sharing groups for this user from the server.
    Each call to this method does make at least one request (an `index` request) to the server. Therefore, client app developers should not make a call to this method too often. For example, calling it when a client app transitions to the foreground, and/or when a user refreshes a sharing group in their UI.
    */
    public func sync(sharingGroupUUID: UUID? = nil) throws {
        try syncHelper(sharingGroupUUID: sharingGroupUUID)
    }
    
    public func delete<DECL: DeclarableObject>(object: DECL) throws {
        try deleteHelper(object: object)
    }
    
    // Returns the same information as from the `downloadDeletion` delegate method-- other clients have removed these files.
    public func filesNeedingDeletion() -> [ObjectDeclaration] {
        return []
    }
    
    // Clients need to call this method to indicate they have deleted files returned from either the deletion delegates or from `filesNeedingDeletion`.
    public func deletedFiles<DECL: DeclarableObject>(object: DECL) {
    }
    
    // MARK: Download
    
    // The list of files returned here survive app relaunch. A given object declaration will appear at most once in the returned list.
    public func filesNeedingDownload(sharingGroupUUID: UUID) throws -> [(declaration: ObjectDeclaration, downloads: Set<FileDownload>)] {
        let filtered = sharingGroups.filter { $0.sharingGroupUUID == sharingGroupUUID.uuidString }
        guard filtered.count == 1 else {
            throw SyncServerError.unknownSharingGroup
        }
        
        return try filesNeedingDownloadHelper(sharingGroupUUID: sharingGroupUUID)
    }
    
    // This method is typically used to trigger downloads of files indicated in filesNeedingDownload, but it can also be used to trigger downloads independently of that.
    func startDownloads<DECL: DeclarableObject, DWL: DownloadableFile>(declaration: DECL, files: Set<DWL>) throws {
    }
    
    // MARK: Sharing
    
    // The sharing groups in which the signed in user is a member.
    public var sharingGroups: [ServerShared.SharingGroup] {
        return _sharingGroups
    }
    
    // MARK: Unqueued requests-- these will fail if they involve a file or other object currently queued for upload or deletion. They will also fail if the network is offline.

    public func createSharingGroup(sharingGroup: UUID, sharingGroupName: String? = nil) {
    }
    
    public func updateSharingGroup(sharingGroup: UUID, newSharingGroupName: String) {
    }
    
    // Remove the current user from the sharing group.
    public func removeFromSharingGroup(sharingGroup: UUID) {
    }
    
    public func createSharingInvitation(withPermission permission:ServerShared.Permission, sharingGroupUUID: String, numberAcceptors: UInt, allowSharingAcceptance: Bool = true, completion:((_ invitationCode:String?, Error?)->(Void))?) {
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

