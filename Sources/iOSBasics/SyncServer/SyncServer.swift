import Foundation
import SQLite
import iOSShared
import ServerShared
import iOSSignIn
import UIKit

public class SyncServer {
    // This *must* be set by the caller/user of this class before use of methods of this class.
    public weak var delegate: SyncServerDelegate! {
        set {
            _delegator = Delegator(delegate: newValue, delegateDispatchQueue: dispatchQueue)
        }
        
        // Don't use this getter internally. Use `delegator` to call delegate methods.
        get {
            assert(false)
            return nil
        }
    }

    // Set these before use of methods of this class.
    public weak var credentialsDelegate: SyncServerCredentials!
    public weak var helperDelegate:SyncServerHelpers!
    
    // Use these to call delegate methods.
    private var _delegator: Delegator!
    func delegator(callDelegate: @escaping (SyncServerDelegate)->()) {
        _delegator.call(callback: callDelegate)
    }

    let configuration: Configuration
    let db: Connection

    let hashingManager: HashingManager
    private(set) var api:ServerAPI!
    let dispatchQueue: DispatchQueue
    var signIns: SignIns
    
    // Maps from objectType to `DeclarableObject & ObjectDownloadHandler`.
    var objectDeclarations = [String: DeclarableObject & ObjectDownloadHandler]()

    /// Create a SyncServer instance.
    ///
    /// - Parameters:
    ///     - hashingManager: Used to compute hashes of files for upload and
    ///         download.
    ///     - db: SQLite database connection
    ///     - configuration: The sync server configuration.
    ///     - signIns: Sign in helper for when iOSSignIn is used.
    ///         The caller must retain the instance and call the
    ///         `SignInManagerDelegate` methods on the SignIns object when the sign
    ///         in state changes. This connects the iOSSignIn package to the
    ///         iOSBasics package.
    ///     - dispatchQueue: used to call `SyncServerDelegate` methods.
    ///         (`SyncServerCredentials` and `SyncServerHelpers` methods may be called on any queue.)
    ///         Also used for any callbacks defined on this interface.
    public init(hashingManager: HashingManager,
        db:Connection,
        configuration: Configuration,
        signIns: SignIns,
        dispatchQueue: DispatchQueue = DispatchQueue.main) throws {
        self.configuration = configuration
        self.db = db
        self.hashingManager = hashingManager
        self.dispatchQueue = dispatchQueue
        
        try Database.setup(db: db)

        self.signIns = signIns
        
        guard let api = ServerAPI(database: db, hashingManager: hashingManager, delegate: self, config: configuration) else {
            throw SyncServerError.internalError("Could not create ServerAPI")
        }
        self.api = api
        
        signIns.cloudFolderName = configuration.cloudFolderName
        signIns.api = api
        credentialsDelegate = signIns
        signIns.delegator = delegator
        signIns.syncServer = self
    }
    
    // MARK: Background network requests
    
    public func application(_ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void) {
        api.networking.application(application, handleEventsForBackgroundURLSession: identifier, completionHandler: completionHandler)
    }
    
    // MARK: Declaring object types.
    
    // You must register all objects every time the app starts.
    // Some of these can be for:
    //  * new objects, e.g., for the first time an app launching.
    //  * existing existing objects-- e.g., this will be the ongoing typical case.
    // To provide a migration path, it is acceptable to extend specific existing DeclarableObject's (i.e., with specific objectTypes) by adding new DeclarableFile's, or to register entirely new DeclarableObject's.
    // Older or deprecated DeclarableObject's should still be registered on each app launch, unless new downloads can never happen for those DeclarableObject's. They should never happen also even for existing files when an app is removed and re-installed too.
    // It is not acceptable to remove DeclarableFile's from existing DeclarableObject's.
    // This class keeps strong references to the passed objects.
    public func register(object: DeclarableObject & ObjectDownloadHandler) throws {
        try declarationHelper(object: object)
    }
    
    // MARK: Persistent queuing for upload, download, and deletion.
    
    // The first upload for a specific object instance (i.e., with a specific fileGroupUUID)
    // If you upload an object that has a fileGroupUUID which is already queued or in progress of uploading, your request will be queued.
    // All files that end up being uploaded in the same queued batch must either be v0 (their first upload) or vN (not their first upload). It is an error to attempt to upload v0 and vN files together in the same batch. This issue may not always be detected (i.e., an error thrown by this call). An error might instead be thrown on a subsequent call to `sync`.
    // In this last regard, it is a best practice to do a v0 upload for all files in a declared object in it's first `queue` call. This way, having both v0 and vN files in the same queued batch *cannot* occur.
    // Uploads are done on a background networking URLSession.
    // You must do at least one `sync` call prior to this call after installing the app. (Not per launch of the app-- these results are persisted).
    public func queue(upload: UploadableObject) throws {
        try queueHelper(upload: upload)
    }

    // This method is typically used to trigger downloads of files indicated in filesNeedingDownload, but it can also be used to trigger downloads independently of that.
    // The files must have been uploaded by this client before, or be available because it was seen in `filesNeedingDownload`.
    // If you queue an object that has a fileGroupUUID which is already queued or in progress of downloading, your request will be queued.
    public func queue<DWL: DownloadableObject>(download: DWL) throws {
        try queueHelper(download: download)
    }
    
    public func queue(objectDeletion fileGroupUUID: UUID, pushNotificationMessage: String? = nil) throws {
        try deleteHelper(object: fileGroupUUID, pushNotificationMessage: pushNotificationMessage)
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
    
    public enum QueueType {
        case upload
        case deletion
        case download
    }
    
    // Is a particular file group being uploaded, deleted, or downloaded?
    public func isQueued(_ queueType: QueueType, fileGroupUUID: UUID) throws -> Bool {
        return try isQueuedHelper(queueType, fileGroupUUID: fileGroupUUID)
    }
    
    // Return the number of queued objects (not files) of the particular type, across sharing groups.
    public func numberQueued(_ queueType: QueueType) throws -> Int {
        return try numberQueuedHelper(queueType)
    }

    // Returns the same information as from the `downloadDeletion` delegate method-- other clients have removed these files.
    // Returns fileGroupUUID's of the objects needing local deletion-- they are deleted on the server but need local deletion.
    public func objectsNeedingLocalDeletion() throws -> [UUID]  {
        return try objectsNeedingLocalDeletionHelper()
    }
    
    // Clients need to call this method to indicate they have deleted objects returned from either the deletion delegates or from `objectsNeedingDeletion`.
    // These files must have been already deleted on the server.
    public func markAsDeletedLocally(object fileGroupUUID: UUID) throws {
        try objectDeletedLocallyHelper(object: fileGroupUUID)
    }

    // The list of files returned here survive app relaunch. A given object declaration will appear at most once in the returned list.
    // If a specific fileGroupUUID is already being downloaded, or queued for download, then `DownloadObject`'s with this fileGroupUUID will not be returned.
    // If specific files are `gone`, then they will be returned (in the relevant `DownloadObject`) as needing download.
    // TODO: `DownloadObject` has a sharingGroupUUID member, but we're passing a sharingGroupUUID-- so that's not really needed.
    public func objectsNeedingDownload(sharingGroupUUID: UUID, includeGone: Bool = false) throws -> [DownloadObject] {
        let filtered = try sharingGroups().filter { $0.sharingGroupUUID == sharingGroupUUID }
        guard filtered.count == 1 else {
            throw SyncServerError.sharingGroupNotFound
        }
        
        return try filesNeedingDownloadHelper(sharingGroupUUID: sharingGroupUUID, includeGone: includeGone)
    }
    
    // Do any of the files of the object need downloading? Analogous to `objectsNeedingDownload`, but for just a single object in a sharing group.
    public func objectNeedsDownload(fileGroupUUID: UUID, includeGone: Bool = false) throws -> DownloadObject? {
        return try objectNeedsDownloadHelper(object:fileGroupUUID, includeGone: includeGone)
    }

    // Call this method so that, after you download an object, it doesn't appear again in `objectsNeedingDownload` (for those file versions).
    public func markAsDownloaded<DWL: DownloadableObject>(object: DWL) throws {
        try markAsDownloadedHelper(object: object)
    }
    
    // Call this method so that, after you download an file, it doesn't appear again in `objectsNeedingDownload` (for that file version).
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

    // Also does a `sync` after successful creation. `completion` returns SyncServerError.networkNotReachable if the network is not reachable.
    public func createSharingGroup(sharingGroupUUID: UUID, sharingGroupName: String? = nil, completion:@escaping (Error?)->()) {
        createSharingGroupHelper(sharingGroupUUID: sharingGroupUUID, sharingGroupName: sharingGroupName) { [weak self] error in
            self?.dispatchQueue.async {
                completion(error)
            }
        }
    }
    
    // Also does a `sync` after successful update. `completion` returns SyncServerError.networkNotReachable if the network is not reachable.
    public func updateSharingGroup(sharingGroupUUID: UUID, newSharingGroupName: String?, completion:@escaping (Error?)->()) {
        updateSharingGroupHelper(sharingGroupUUID: sharingGroupUUID, newSharingGroupName: newSharingGroupName) { [weak self] error in
            self?.dispatchQueue.async {
                completion(error)
            }
        }
    }

    // Remove the current user from the sharing group. Also does a `sync` after successful update. `completion` returns SyncServerError.networkNotReachable if the network is not reachable.
    public func removeFromSharingGroup(sharingGroupUUID: UUID, completion:@escaping (Error?)->()) {
        removeFromSharingGroupHelper(sharingGroupUUID: sharingGroupUUID) { [weak self] error in
            self?.dispatchQueue.async {
                completion(error)
            }
        }
    }
    
    // MARK: Sharing invitations

    // The non-error result is the code for the sharing invitation, a UUID.  `completion` returns SyncServerError.networkNotReachable if the network is not reachable.
    public func createSharingInvitation(withPermission permission:Permission, sharingGroupUUID: UUID, numberAcceptors: UInt, allowSocialAcceptance: Bool, expiryDuration:TimeInterval = ServerConstants.sharingInvitationExpiryDuration, completion: @escaping (Swift.Result<UUID, Error>)->()) {
    
        guard api.networking.reachability.isReachable else {
            logger.info("Could not sync: Network not reachable")
            completion(.failure(SyncServerError.networkNotReachable))
            return
        }
        
        api.createSharingInvitation(withPermission: permission, sharingGroupUUID: sharingGroupUUID, numberAcceptors: numberAcceptors, allowSocialAcceptance: allowSocialAcceptance, expiryDuration: expiryDuration) { [weak self] result in
            guard let self = self else { return }
            self.dispatchQueue.async {
                completion(result)
            }
        }
    }
    
    /// On success, automatically syncs index before returning. `completion` returns SyncServerError.networkNotReachable if the network is not reachable.
    public func redeemSharingInvitation(sharingInvitationUUID:UUID, completion: @escaping (Swift.Result<RedeemResult, Error>)->()) {

        guard api.networking.reachability.isReachable else {
            logger.info("Could not sync: Network not reachable")
            completion(.failure(SyncServerError.networkNotReachable))
            return
        }
        
        api.redeemSharingInvitation(sharingInvitationUUID: sharingInvitationUUID, cloudFolderName: configuration.cloudFolderName) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let redeemResult):
                self.getIndex(sharingGroupUUID: redeemResult.sharingGroupUUID)
            case .failure:
                break
            }
            
            self.dispatchQueue.async {
                completion(result)
            }
        }
    }
    
    /// `completion` returns SyncServerError.networkNotReachable if the network is not reachable.
    public func getSharingInvitationInfo(sharingInvitationUUID: UUID, completion: @escaping (Swift.Result<SharingInvitationInfo, Error>)->()) {
        guard api.networking.reachability.isReachable else {
            logger.info("Could not sync: Network not reachable")
            completion(.failure(SyncServerError.networkNotReachable))
            return
        }
        
        api.getSharingInvitationInfo(sharingInvitationUUID: sharingInvitationUUID) { [weak self] result in
            self?.dispatchQueue.async {
                completion(result)
            }
        }
    }
    
    // MARK: Push Notifications
    
    /// `completion` returns SyncServerError.networkNotReachable if the network is not reachable.
    public func registerPushNotificationToken(_ token: String, completion: @escaping (Error?)->()) {
        guard api.networking.reachability.isReachable else {
            logger.info("Could not sync: Network not reachable")
            completion(SyncServerError.networkNotReachable)
            return
        }
        
        api.registerPushNotificationToken(token) { [weak self] error in
            self?.dispatchQueue.async {
                completion(error)
            }
        }
    }
}

