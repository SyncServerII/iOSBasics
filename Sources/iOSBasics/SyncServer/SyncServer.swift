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
    var signIns: SignIns
    
    // Maps from objectType to `DeclarableObject & ObjectDownloadHandler`.
    var objectDeclarations = [String: DeclarableObject & ObjectDownloadHandler]()
    
    var deferredOperationTimer: Timer?

    // Delegate and callback queue.
    let dispatchQueue: DispatchQueue

    // Serializing *all* operations acting on iOSBasics held data structures with this queue so we don't mess up our database tables and and in-memory structures. E.g., with delegate calls from networking, timer callbacks, and client calls to the iOSBasics interface. (By default `DispatchQueue` gives a serial queue).
    let serialQueue = DispatchQueue(label: "iOSBasics")

    let requestable:NetworkRequestable
    let backgroundAsssertable: BackgroundAsssertable
    
    /// Create a SyncServer instance.
    ///
    /// - Parameters:
    ///     - hashingManager: Used to compute hashes of files for upload and
    ///         download.
    ///     - db: SQLite database connection
    ///     - requestable: Can network requests be made? SyncServer will retain this object.
    ///     - configuration: The sync server configuration.
    ///     - signIns: Sign in helper for when iOSSignIn is used.
    ///         The caller must retain the instance and call the
    ///         `SignInManagerDelegate` methods on the SignIns object when the sign
    ///         in state changes. This connects the iOSSignIn package to the
    ///         iOSBasics package.
    ///     - backgroundAsssertable: To ensure necessary tasks execute properly if app transitions to the background.
    ///     - dispatchQueue: used to call `SyncServerDelegate` methods.
    ///         (`SyncServerCredentials` and `SyncServerHelpers` methods may be called on any queue.)
    ///         Also used for any callbacks defined on this interface.
    public init(hashingManager: HashingManager,
        db:Connection,
        requestable:NetworkRequestable,
        configuration: Configuration,
        signIns: SignIns,
        backgroundAsssertable: BackgroundAsssertable,
        dispatchQueue: DispatchQueue = DispatchQueue.main) throws {
        self.configuration = configuration
        self.db = db
        self.hashingManager = hashingManager
        self.dispatchQueue = dispatchQueue
        self.requestable = requestable
        self.backgroundAsssertable = backgroundAsssertable
        
        try Database.setup(db: db)

        self.signIns = signIns
        
        guard let api = ServerAPI(database: db, hashingManager: hashingManager, delegate: self, serialQueue: serialQueue, backgroundAsssertable: backgroundAsssertable, config: configuration) else {
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
        serialQueue.sync { [weak self] in
            guard let self = self else { return }
            self.api.networking.application(application, handleEventsForBackgroundURLSession: identifier, completionHandler: completionHandler)
        }
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
    // This call is synchronous-- it doesn't call delegates or other callbacks after it completes.
    public func register(object: DeclarableObject & ObjectDownloadHandler) throws {
        // `sync` because this method is itself synchronous.
        try serialQueue.sync { [weak self] in
            guard let self = self else { return }
            try self.declarationHelper(object: object)
        }
    }
    
    // MARK: Persistent queuing for upload, download, and deletion.
    
    // The first upload for a specific object instance (i.e., with a specific fileGroupUUID), or a subsequent upload of the same instance.
    // If you upload an object that has a fileGroupUUID which is already queued or in progress of uploading, your request will be queued. i.e., the upload will not be triggered right now. It will be triggered later.
    // All files that end up being uploaded in the same queued batch must either be v0 (their first upload) or vN (not their first upload). It is an error to attempt to upload v0 and vN files together in the same batch. This issue may not always be detected immediately (i.e., an error thrown by this call). An error might instead be thrown on a subsequent call to `sync`.
    // In this last regard, it is a best practice to do a v0 upload for all files in a declared object in it's first `queue` call. This way, having both v0 and vN files in the same queued batch *cannot* occur.
    // Uploads are done on a background networking URLSession.
    // You must do at least one `sync` call prior to this call after installing the app. (Not per launch of the app-- these results are persisted).
    public func queue(upload: UploadableObject) throws {
        // `sync` because the immediate effect of this call is short running.

        try backgroundAsssertable.syncRun { [weak self] in
            guard let self = self else { return }

            try self.serialQueue.sync { [weak self] in
                guard let self = self else { return }
                
                try self.queueHelper(upload: upload)
            }
        } expiry: { [weak self] in
            guard let self = self else { return }
            self.delegator { delegate in
                delegate.userEvent(self, event: .error(SyncServerError.backgroundAssertionExpired))
            }
        }
    }

    // This method is typically used to trigger downloads of files indicated in filesNeedingDownload, but it can also be used to trigger downloads independently of that.
    // The files must have been uploaded by this client before, or be available because it was seen in `filesNeedingDownload`.
    // If you queue an object that has a fileGroupUUID which is already queued or in progress of downloading, your request will be queued. i.e., the download will not be triggered right now. It will be triggered later.
    public func queue<DWL: DownloadableObject>(download: DWL) throws {
        // `sync` because the immediate effect of this call is short running.

        try backgroundAsssertable.syncRun { [weak self] in
            guard let self = self else { return }
            
            try self.serialQueue.sync { [weak self] in
                guard let self = self else { return }
                try self.queueHelper(download: download)
            }
        } expiry: { [weak self] in
            guard let self = self else { return }
            self.delegator { delegate in
                delegate.userEvent(self, event: .error(SyncServerError.backgroundAssertionExpired))
            }
        }
    }
    
    // The deletion of an entire existing object, referenced by its file group.
    public func queue(objectDeletion fileGroupUUID: UUID, pushNotificationMessage: String? = nil) throws {
        // `sync` because the immediate effect of this call is short running.
            
        try backgroundAsssertable.syncRun { [weak self] in
            guard let self = self else { return }

            try self.serialQueue.sync { [weak self] in
                guard let self = self else { return }
                try self.deleteHelper(object: fileGroupUUID, pushNotificationMessage: pushNotificationMessage)
            }
        } expiry: { [weak self] in
            guard let self = self else { return }
            self.delegator { delegate in
                delegate.userEvent(self, event: .error(SyncServerError.backgroundAssertionExpired))
            }
        }
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
    Throws SyncServerError.networkNotReachable if there is no network connection.
    */
    public func sync(sharingGroupUUID: UUID? = nil) throws {
        guard requestable.canMakeNetworkRequests else {
            logger.info("Could not sync: Network not reachable")
            throw SyncServerError.networkNotReachable
        }

        backgroundAsssertable.asyncRun { [weak self] completion in
            guard let self = self else { return }
            
            self.serialQueue.async { [weak self] in
                guard let self = self else { return }
                
                do {
                    try self.syncHelper(completion: completion, sharingGroupUUID: sharingGroupUUID)
                } catch let error {
                    self.delegator { delegate in
                        delegate.userEvent(self, event: .error(error))
                    }
                }
            }
        } expiry: { [weak self] in
            guard let self = self else { return }
            self.delegator { delegate in
                delegate.userEvent(self, event: .error(SyncServerError.backgroundAssertionExpired))
            }
        }
    }
    
    // MARK: Getting information: These are local operations that do not interact with the server.
    
    public enum QueueType {
        case upload
        case deletion
        case download
    }
    
    public struct LocalFileInfo {
        // Nil if an index was obtained from the server, but the file hasn't yet been downloaded.
        public let fileVersion: FileVersionInt?
    }
    
    // Returns information on the most recent file version uploaded, or the last version downloaded.
    public func localFileInfo(forFileUUID fileUUID: UUID) throws -> LocalFileInfo {
        return try serialQueue.sync {
            return try self.fileInfoHelper(fileUUID: fileUUID)
        }
    }
    
    // Is a particular file group being uploaded, deleted, or downloaded?
    public func isQueued(_ queueType: QueueType, fileGroupUUID: UUID) throws -> Bool {
        // `sync` because the immediate effect of this call is short running.
        return try serialQueue.sync { [weak self] in
            guard let self = self else { return false }
            return try self.isQueuedHelper(queueType, fileGroupUUID: fileGroupUUID)
        }
    }
    
    // Return the number of queued objects (not files) of the particular type, across sharing groups.
    public func numberQueued(_ queueType: QueueType) throws -> Int {
        // `sync` because the immediate effect of this call is short running.
        return try serialQueue.sync { [weak self] in
            guard let self = self else { return 0 }
            return try self.numberQueuedHelper(queueType)
        }
    }

    // Returns the same information as from the `downloadDeletion` delegate method-- other clients have removed these files.
    // Returns fileGroupUUID's of the objects needing local deletion-- they are deleted on the server but need local deletion.
    public func objectsNeedingLocalDeletion() throws -> [UUID]  {
        // `sync` because the immediate effect of this call is short running.
        return try serialQueue.sync { [weak self] in
            guard let self = self else { return [] }
            return try self.objectsNeedingLocalDeletionHelper()
        }
    }
    
    // Clients need to call this method to indicate they have deleted objects returned from either the deletion delegates or from `objectsNeedingDeletion`.
    // These files must have been already deleted on the server.
    public func markAsDeletedLocally(object fileGroupUUID: UUID) throws {
        // `sync` because the immediate effect of this call is short running.
        try serialQueue.sync { [weak self] in
            guard let self = self else { return }
            try self.objectDeletedLocallyHelper(object: fileGroupUUID)
        }
    }

    // The list of files returned here survive app relaunch. A given object declaration will appear at most once in the returned list.
    // If a specific fileGroupUUID is already being downloaded, or queued for download, then `DownloadObject`'s with this fileGroupUUID will not be returned.
    // If specific files are `gone`, then they will be returned (in the relevant `DownloadObject`) as needing download.
    // TODO: `DownloadObject` has a sharingGroupUUID member, but we're passing a sharingGroupUUID-- so that's not really needed.
    public func objectsNeedingDownload(sharingGroupUUID: UUID, includeGone: Bool = false) throws -> [DownloadObject] {
        // `sync` because the immediate effect of this call is short running.
        return try serialQueue.sync { [weak self] in
            guard let self = self else { return [] }
            
            let filtered = try self.getSharingGroupsHelper().filter { $0.sharingGroupUUID == sharingGroupUUID }
            guard filtered.count == 1 else {
                throw SyncServerError.sharingGroupNotFound
            }
            
            return try self.filesNeedingDownloadHelper(sharingGroupUUID: sharingGroupUUID, includeGone: includeGone)
        }
    }
    
    // Do any of the files of the object need downloading? Analogous to `objectsNeedingDownload`, but for just a single object in a sharing group. Nil is returned if the object doesn't need downloading.
    public func objectNeedsDownload(fileGroupUUID: UUID, includeGone: Bool = false) throws -> DownloadObject? {
        // `sync` because the immediate effect of this call is short running.
        return try serialQueue.sync { [weak self] in
            guard let self = self else { return nil }
            return try self.objectNeedsDownloadHelper(object:fileGroupUUID, includeGone: includeGone)
        }
    }

    // Call this method so that, after you download an object, it doesn't appear again in `objectsNeedingDownload` (for those file versions).
    // This does *not* call `BackgroundAsssertable` methods.
    public func markAsDownloaded<DWL: DownloadableObject>(object: DWL) throws {
        // `sync` because the immediate effect of this call is short running.
        try serialQueue.sync { [weak self] in
            guard let self = self else { return }
            try self.markAsDownloadedHelper(object: object)
        }
    }
    
    // Call this method so that, after you download an file, it doesn't appear again in `objectsNeedingDownload` (for that file version).
    public func markAsDownloaded<DWL: DownloadableFile>(file: DWL) throws {
        // `sync` because the immediate effect of this call is short running.
        try serialQueue.sync { [weak self] in
            guard let self = self else { return }
            try self.markAsDownloadedHelper(file: file)
        }
    }
    
    // MARK: Debugging

    // Logs debugging information for the file.
    public func debug(fileUUID: UUID) throws {
        if let fileTracker = try DownloadFileTracker.fetchSingleRow(db: db, where: DownloadFileTracker.fileUUIDField.description == fileUUID) {
            logger.debug("debug: fileTracker: fileTracker.status: \(fileTracker.status)")
        }
        else {
            logger.debug("debug: fileTracker: No DownloadFileTracker with UUID: \(fileUUID)")
        }

        if let fileEntry = try DirectoryFileEntry.fetchSingleRow(db: db, where: DirectoryFileEntry.fileUUIDField.description == fileUUID) {
            logger.debug("debug: fileEntry: fileEntry.fileVersion: \(String(describing: fileEntry.fileVersion)); fileEntry.serverFileVersion: \(String(describing: fileEntry.serverFileVersion))")
        }
        else {
            logger.debug("debug: fileEntry: No DirectoryFileEntry with UUID: \(fileUUID)")
        }
    }

    // Logs debugging information for the object.
    public func debug(fileGroupUUID: UUID) throws {
        if let _ = try DownloadObjectTracker.fetchSingleRow(db: db, where: DownloadObjectTracker.fileGroupUUIDField.description == fileGroupUUID) {
            logger.debug("debug: objectTracker: exists.")
        }
        else {
            logger.debug("debug: objectTracker: No DownloadObjectTracker with UUID: \(fileGroupUUID)")
        }
    }
    
    // MARK: Sharing
    
    // The sharing groups in which the signed in user is a member.
    public func sharingGroups() throws -> [iOSBasics.SharingGroup]  {
        // `sync` because the immediate effect of this call is short running.
        return try serialQueue.sync { [weak self] in
            guard let self = self else { return [] }
            return try self.getSharingGroupsHelper()
        }
    }
    
    // MARK: Unqueued server requests-- these will fail if they involve a file or other object currently queued for upload or deletion. They will also fail if the network is offline.

    // MARK: Sharing groups

    // Also does a `sync` after successful creation. `completion` returns SyncServerError.networkNotReachable if the network is not reachable.
    public func createSharingGroup(sharingGroupUUID: UUID, sharingGroupName: String? = nil, completion:@escaping (Error?)->()) {
        serialQueue.async { [weak self] in
            guard let self = self else { return }

            self.createSharingGroupHelper(sharingGroupUUID: sharingGroupUUID, sharingGroupName: sharingGroupName) { [weak self] error in
                guard let self = self else { return }
                
                self.dispatchQueue.async {
                    completion(error)
                }
            }
        }
    }
    
    // Also does a `sync` after successful update. `completion` returns SyncServerError.networkNotReachable if the network is not reachable.
    public func updateSharingGroup(sharingGroupUUID: UUID, newSharingGroupName: String?, completion:@escaping (Error?)->()) {
        serialQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.updateSharingGroupHelper(sharingGroupUUID: sharingGroupUUID, newSharingGroupName: newSharingGroupName) { [weak self] error in
                guard let self = self else { return }

                self.dispatchQueue.async {
                    completion(error)
                }
            }
        }
    }

    // Remove the current user from the sharing group. Also does a `sync` after successful update. `completion` returns SyncServerError.networkNotReachable if the network is not reachable.
    public func removeFromSharingGroup(sharingGroupUUID: UUID, completion:@escaping (Error?)->()) {
        serialQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.removeFromSharingGroupHelper(sharingGroupUUID: sharingGroupUUID) { [weak self] error in
                guard let self = self else { return }

                self.dispatchQueue.async {
                    completion(error)
                }
            }
        }
    }
    
    // MARK: Sharing invitations

    // The non-error result is the code for the sharing invitation, a UUID.  `completion` returns SyncServerError.networkNotReachable if the network is not reachable.
    public func createSharingInvitation(withPermission permission:Permission, sharingGroupUUID: UUID, numberAcceptors: UInt, allowSocialAcceptance: Bool, expiryDuration:TimeInterval = ServerConstants.sharingInvitationExpiryDuration, completion: @escaping (Swift.Result<UUID, Error>)->()) {
    
        guard requestable.canMakeNetworkRequests else {
            logger.info("Could not sync: Network not reachable")
            completion(.failure(SyncServerError.networkNotReachable))
            return
        }
        
        serialQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.api.createSharingInvitation(withPermission: permission, sharingGroupUUID: sharingGroupUUID, numberAcceptors: numberAcceptors, allowSocialAcceptance: allowSocialAcceptance, expiryDuration: expiryDuration) { [weak self] result in
                guard let self = self else { return }
                
                self.dispatchQueue.async {
                    completion(result)
                }
            }
        }
    }
    
    /// On success, automatically syncs index before returning. `completion` returns SyncServerError.networkNotReachable if the network is not reachable.
    public func redeemSharingInvitation(sharingInvitationUUID:UUID, completion: @escaping (Swift.Result<RedeemResult, Error>)->()) {

        guard requestable.canMakeNetworkRequests else {
            logger.info("Could not sync: Network not reachable")
            completion(.failure(SyncServerError.networkNotReachable))
            return
        }

        serialQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.api.redeemSharingInvitation(sharingInvitationUUID: sharingInvitationUUID, cloudFolderName: self.configuration.cloudFolderName) { [weak self] result in
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
    }
    
    /// `completion` returns SyncServerError.networkNotReachable if the network is not reachable.
    public func getSharingInvitationInfo(sharingInvitationUUID: UUID, completion: @escaping (Swift.Result<SharingInvitationInfo, Error>)->()) {
        guard requestable.canMakeNetworkRequests else {
            logger.info("Could not sync: Network not reachable")
            completion(.failure(SyncServerError.networkNotReachable))
            return
        }

        serialQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.api.getSharingInvitationInfo(sharingInvitationUUID: sharingInvitationUUID) { [weak self] result in
                guard let self = self else { return }

                self.dispatchQueue.async {
                    completion(result)
                }
            }
        }
    }
    
    // MARK: Push Notifications
    
    /// `completion` returns SyncServerError.networkNotReachable if the network is not reachable.
    public func registerPushNotificationToken(_ token: String, completion: @escaping (Error?)->()) {
        guard requestable.canMakeNetworkRequests else {
            logger.info("Could not sync: Network not reachable")
            completion(SyncServerError.networkNotReachable)
            return
        }

        serialQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.api.registerPushNotificationToken(token) { [weak self] error in
                guard let self = self else { return }

                self.dispatchQueue.async {
                    completion(error)
                }
            }
        }
    }
}

