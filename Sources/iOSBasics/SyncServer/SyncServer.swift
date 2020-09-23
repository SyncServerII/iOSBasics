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
    
    #warning("When I integrate `SignIns`, use this instead of `SyncServerCredentials`. And then remove cloudStorageType from `GenericCredentials`.")
    var signIns: SignIns!
    
    let hashingManager: HashingManager
    private(set) var api:ServerAPI!
    let delegateDispatchQueue: DispatchQueue
    
    /// Create a SyncServer instance.
    ///
    /// - Parameters:
    ///     - hashingManager: Used to compute hashes of files for upload and
    ///         download.
    ///     - db: SQLite database connection
    ///     - configuration: The sync server configuration.
    ///     - delegateDispatchQueue: used to call `SyncServerDelegate` methods.
    ///         (`SyncServerCredentials` methods may be called on any queue.)
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
    
    // MARK: Persistent queuing for upload, download, and deletion.
    
    // If you upload an object that has a fileGroupUUID which is already queued or in progress of uploading, your request will be queued.
    // The first time you queue a SyncedObject, this call persistently registers the DeclaredObject portion of the object. Subsequent `queue` calls with the same syncObjectId in the object, must exactly match the DeclaredObject.
    // The `uuid` of files present in the uploads must be in the declaration.
    // All files that end up being uploaded in the same queued batch must either be v0 (their first upload) or vN (not their first upload). It is an error to attempt to upload v0 and vN files together in the same batch. This issue may not always be detected (i.e., an error thrown by this call). An error might instead be thrown on a subsequent call to `sync`.
    // In this last regard, it is a best practice to do a v0 upload for all files in a declared object in it's first `queue` call. This way, having both v0 and vN files in the same queued batch *cannot* occur.
    // Uploads are done on a background networking URLSession.
    // You must do at least one `sync` call prior to this call after installing the app. (Not per launch of the app-- these results are persisted).
    public func queue<DECL: DeclarableObject, UPL:UploadableFile>
        (uploads: Set<UPL>, declaration: DECL) throws {
        try queueHelper(uploads: uploads, declaration: declaration)
    }
    
    // This method is typically used to trigger downloads of files indicated in filesNeedingDownload, but it can also be used to trigger downloads independently of that.
    // The files must have been uploaded by this client before, or be available because it was seen in `filesNeedingDownload`.
    // If you queue an object that has a fileGroupUUID which is already queued or in progress of downloading, your request will be queued.
    func queue<DECL: DeclarableObject, DWL: DownloadableFile>(downloads: Set<DWL>, declaration: DECL) throws {
        try queueHelper(downloads: downloads, declaration: declaration)
    }
    
    public func queue<DECL: DeclarableObject>(deletion object: DECL) throws {
        try deleteHelper(object: object)
    }
    
    /* This performs a variety of actions:
    1) It triggers any next pending uploads. In general, after a set of uploads queued by your call(s) to the SyncServer `queue` uploads method, further uploads are not automatically initiated. It's up to the caller of this interface to call `sync` periodically to drive that. It's likely best that `sync` only be called while the app is in the foreground-- to avoid penalties (e.g., increased latencies) incurred by initating network requests, from other networking requests, while the app is in the background. Uploads are carried out using a background URLSession and so can run while the app is in the background.
    2) Triggers any next pending downloads.
    3) It checks if vN deferred uploads server requests have completed.
    4) If a non-nil sharingGroupUUID is given, this fetches the index for all files in that sharing group from the server. If successful, the syncCompleted delegate method is called, and:
        a) the `sharingGroups` property has been updated
        b) the `filesNeedingDownload` method can be called to determine any files needing downloading for the sharing group.
    5) If a nil sharingGroupUUID is given, this fetches all sharing groups for this user from the server.
    Each call to this method does make at least one request (an `index` request) to the server. Therefore, client app developers should not make a call to this method too often. For example, calling it when a client app transitions to the foreground, and/or when a user refreshes a sharing group in their UI.
    At least one call to this method should be done prior to any other call on this interface. For example, such a call is required for non-owning (e.g., Facebook users) in order for them to upload files.
    */
    public func sync(sharingGroupUUID: UUID? = nil) throws {
        try syncHelper(sharingGroupUUID: sharingGroupUUID)
    }
    
    // MARK: Getting information: These are local operations that do not interact with the server.

    // Returns the same information as from the `downloadDeletion` delegate method-- other clients have removed these files.
    public func objectsNeedingDeletion() throws -> [ObjectDeclaration] {
        return try objectsNeedingDeletionHelper()
    }
    
    // Clients need to call this method to indicate they have deleted objects returned from either the deletion delegates or from `objectsNeedingDeletion`.
    public func markAsDeleted<DECL: DeclarableObject>(object: DECL) throws {
        try objectDeletedHelper(object: object)
    }
        
    // The list of files returned here survive app relaunch. A given object declaration will appear at most once in the returned list.
    public func filesNeedingDownload(sharingGroupUUID: UUID) throws -> [(declaration: ObjectDeclaration, downloads: Set<FileDownload>)] {
        let filtered = try sharingGroups().filter { $0.sharingGroupUUID == sharingGroupUUID }
        guard filtered.count == 1 else {
            throw SyncServerError.unknownSharingGroup
        }
        
        return try filesNeedingDownloadHelper(sharingGroupUUID: sharingGroupUUID)
    }
    
    // Call this method so that, after you download a file, it doesn't appear again in `filesNeedingDownload` (for that file version).
    public func markAsDownloaded<DWL: DownloadableFile>(file: DWL) throws {
        try markAsDownloadedHelper(file: file)
    }
    
    // MARK: Sharing
    
    // The sharing groups in which the signed in user is a member.
    public func sharingGroups() throws -> [iOSBasics.SharingGroup]  {
        return try getSharingGroupsHelper()
    }
    
    // MARK: Unqueued server requests-- these will fail if they involve a file or other object currently queued for upload or deletion. They will also fail if the network is offline.

    // MARK: Sharing groups
    
    public func createSharingGroup(sharingGroupUUID: UUID, sharingGroupName: String? = nil, completion:@escaping (Error?)->()) {
        createSharingGroupHelper(sharingGroupUUID: sharingGroupUUID, sharingGroupName: sharingGroupName, completion: completion)
    }
    
    public func updateSharingGroup(sharingGroupUUID: UUID, newSharingGroupName: String, completion:@escaping (Error?)->()) {
        updateSharingGroupHelper(sharingGroupUUID: sharingGroupUUID, newSharingGroupName: newSharingGroupName, completion: completion)
    }
    
    // Remove the current user from the sharing group.
    public func removeFromSharingGroup(sharingGroupUUID: UUID, completion:@escaping (Error?)->()) {
        removeFromSharingGroupHelper(sharingGroupUUID: sharingGroupUUID, completion: completion)
    }
    
    // MARK: Sharing invitation

    public func createSharingInvitation(withPermission permission:ServerShared.Permission, sharingGroupUUID: String, numberAcceptors: UInt, allowSharingAcceptance: Bool = true, completion:((_ invitationCode:String?, Error?)->(Void))?) {
    }
}

