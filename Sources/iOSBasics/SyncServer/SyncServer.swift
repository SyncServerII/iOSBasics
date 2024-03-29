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
    ///     - migrationRunner: Provide a means to run database migrations.
    ///         Except for testing this should be nil. When nil, this class provides
    ///         its own `MigrationRunner`.
    ///     - currentUserId: The user id of the current signed in user.
    ///         This is for specific migration/fixes for specific users.
    ///     - dispatchQueue: used to call `SyncServerDelegate` methods.
    ///         (`SyncServerCredentials` and `SyncServerHelpers` methods may be called on any queue.)
    ///         Also used for any callbacks defined on this interface.
    public init(hashingManager: HashingManager,
        db:Connection,
        requestable:NetworkRequestable,
        configuration: Configuration,
        signIns: SignIns,
        backgroundAsssertable: BackgroundAsssertable,
        migrationRunner: MigrationRunner? = nil,
        currentUserId: UserId? = nil,
        dispatchQueue: DispatchQueue = DispatchQueue.main) throws {
        self.configuration = configuration
        self.db = db
        self.hashingManager = hashingManager
        self.dispatchQueue = dispatchQueue
        self.requestable = requestable
        self.backgroundAsssertable = backgroundAsssertable
        
        try Database.setup(db: db)
        
        let runner: MigrationRunner
        if let migrationRunner = migrationRunner {
            runner = migrationRunner
        }
        else {
            runner = try Migration(db: db)
        }
        
        try runner.run(
            migrations: Migration.metadata(db: db),
            contentChanges: Migration.content(configuration: configuration, currentUserId: currentUserId, db: db))
        
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
    
    // MARK: App state methods
    
    public func appChangesState(to appState: AppState) throws {
        if appState == .background {
            stopTimedDeferredCheckIfNeeded()
        }
        
        // Going to leave restarting the timer, if needed, to the next `sync`.
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
    // See https://github.com/SyncServerII/Neebla/issues/25#issuecomment-898940988 for the rules prioritizing deletions, uploads, and downloads.
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
    // See https://github.com/SyncServerII/Neebla/issues/25#issuecomment-898940988 for the rules prioritizing deletions, uploads, and downloads.
    public func queue<DWL: DownloadableObject>(download: DWL) throws {
        try backgroundAsssertable.syncRun { [weak self] in
            guard let self = self else { return }
            
            // `sync` because the immediate effect of this call is short running.
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
    
    // There must be a queued download for the file group currently with at least some .downloading status files. I.e., this will restart .downloading files queued by a call to queue(download: ...) above. The downloads have been restarted but not yet triggered. E.g., this relies on the user also doing a pull-down-refresh in the UI. Throws `SyncServerError.noObject` if there were no files downloading for the file group.
    public func restart(download fileGroupUUID: UUID) throws {
        try self.serialQueue.sync { [weak self] in
            guard let self = self else { return }
            try self.restartDownloadHelper(fileGroupUUID: fileGroupUUID)
        }
    }
    
    // The deletion of an entire existing object, referenced by its file group.
    // See https://github.com/SyncServerII/Neebla/issues/25#issuecomment-898940988 for the rules prioritizing deletions, uploads, and downloads.
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
                    logger.error("syncHelper: \(error)")
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
        case deletion // this is an upload.
        case download
    }
    
    public struct FileAttributes {
        // file version downloaded. Nil if an index was obtained from the server, but the file hasn't yet been downloaded.
        public let fileVersion: FileVersionInt?
        
        // The file version on the server. Updated on a sync.
        public let serverVersion: FileVersionInt?
        
        public let creationDate: Date
        public let updateDate: Date?
    }
    
    // Returns attributes tracked by iOSBasics about a file. Returns nil if fileUUID isn't yet known to iOSBasics. A file won't yet be known if a sync for a specific sharing group, in which the file is contained, hasn't yet been done.
    public func fileAttributes(forFileUUID fileUUID: UUID) throws -> FileAttributes? {
        return try serialQueue.sync {
            return try self.fileInfoHelper(fileUUID: fileUUID)
        }
    }
    
    public struct FileGroupAttributes {
        public struct FileAttributes {
            public let fileLabel: String
            public let fileUUID: UUID
        }
        
        public let files: [FileAttributes]
    }

    // Returns attributes tracked by iOSBasics about a file group. Returns nil if fileGroupUUID isn't yet known to iOSBasics. A file group won't yet be known if a sync for a specific sharing group, in which the file group is contained, hasn't yet been done.
    public func fileGroupAttributes(forFileGroupUUID fileGroupUUID: UUID) throws -> FileGroupAttributes? {
        return try serialQueue.sync {
            return try self.fileGroupInfoHelper(fileGroupUUID: fileGroupUUID)
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
    
    // Do any of the files of the object need downloading? Analogous to `objectsNeedingDownload`, but for just a single object in a sharing group. Nil is returned if the object doesn't need downloading (either if the object is already downloading, or if it doesn't need downloading).
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
    
    // Call this method to mark an object as needing to be downloaded.
    public func markAsNotDownloaded<DWL: ObjectNotDownloaded>(object: DWL) throws {
        // `sync` because the immediate effect of this call is short running.
        try serialQueue.sync { [weak self] in
            guard let self = self else { return }
            try self.markAsNotDownloadedHelper(object: object)
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
    
    // Call this method to mark a file as needing to be downloaded.
    public func markAsNotDownloaded(file: FileNotDownloaded) throws {
        // `sync` because the immediate effect of this call is short running.
        try serialQueue.sync { [weak self] in
            guard let self = self else { return }
            try self.markAsNotDownloadedHelper(file: file)
        }
    }
    
    // MARK: Debugging

    // Logs debugging information for the file.
    public func debug(fileUUID: UUID) throws {
        if let fileTracker = try DownloadFileTracker.fetchSingleRow(db: db, where: DownloadFileTracker.fileUUIDField.description == fileUUID) {
            logger.notice("debug: fileTracker: fileTracker.status: \(fileTracker.status)")
        }
        else {
            logger.notice("debug: fileTracker: No DownloadFileTracker with UUID: \(fileUUID)")
        }

        if let fileEntry = try DirectoryFileEntry.fetchSingleRow(db: db, where: DirectoryFileEntry.fileUUIDField.description == fileUUID) {
            logger.notice("debug: fileEntry: fileEntry.fileVersion: \(String(describing: fileEntry.fileVersion)); fileEntry.serverFileVersion: \(String(describing: fileEntry.serverFileVersion))")
        }
        else {
            logger.notice("debug: fileEntry: No DirectoryFileEntry with UUID: \(fileUUID)")
        }
    }
    
    public func debugPendingDownloads() throws -> String? {
        var result = ""
        
        let objectTrackers = try DownloadObjectTracker.fetch(db: db)
        for objectTracker in objectTrackers {
            let fileTrackers = try objectTracker.dependentFileTrackers()
            
            guard fileTrackers.count > 0 else {
                continue
            }
            
            result += "\nDownloadObjectTracker: fileGroupUUID: \(objectTracker.fileGroupUUID)\n"
            
            for fileTracker in fileTrackers {
                result += "\tDownloadFileTracker: fileUUID: \(fileTracker.fileUUID); status: \(fileTracker.status); expiry: \(String(describing: fileTracker.expiry)); numberRetries: \(fileTracker.numberRetries)\n"
            }
        }
        
        guard result.count > 0 else {
            return nil
        }
        
        return result
    }
    
    // Generate debugging information for pending uploads if any. Returns nil if none.
    public func debugPendingUploads() throws -> String? {
        let objectTrackers = try UploadObjectTracker.fetch(db:db)
        guard objectTrackers.count > 0 else {
            return nil
        }
        
        var result = ""
        
        for objectTracker in objectTrackers {
            // Shouldn't happen, but see if this file group is deleted.
            let directoryObject = try DirectoryObjectEntry.fetchSingleRow(db: db, where: DirectoryObjectEntry.fileGroupUUIDField.description == objectTracker.fileGroupUUID)
                    
            result += "UploadObjectTracker: fileGroupUUID: \(objectTracker.fileGroupUUID); v0Upload: \(String(describing: objectTracker.v0Upload)); batchUUID: \(objectTracker.batchUUID); deletedLocally: \(String(describing: directoryObject?.deletedLocally)); deletedOnServer: \(String(describing: directoryObject?.deletedOnServer))\n"
            
            let fileTrackers = try objectTracker.dependentFileTrackers()
            for fileTracker in fileTrackers {
                var canReadFile: Bool?
                var url: URL?
                var nonRelativeURL: URL?
                
                if let localURL = fileTracker.localURL {
                    let read = localURL.canReadFile()
                    
                    if !read {
                        url = localURL
                        nonRelativeURL = URL(fileURLWithPath: localURL.path)
                    }
                    
                    canReadFile = read
                }
                
                let fileEntry = try DirectoryFileEntry.fetchSingleRow(db: db, where: DirectoryFileEntry.fileGroupUUIDField.description == fileTracker.fileUUID)

                result += "\tUploadFileTracker: fileUUID: \(fileTracker.fileUUID); fileVersion: \(String(describing: fileTracker.fileVersion)); status: \(fileTracker.status); uploadIndex: \(fileTracker.uploadIndex); uploadCount: \(fileTracker.uploadCount); expiry: \(String(describing: fileTracker.expiry)); canReadFile: \(String(describing: canReadFile)); mimeType: \(String(describing: fileTracker.mimeType)); uploadCopy: \(String(describing: fileTracker.uploadCopy)); deletedLocally: \(String(describing: fileEntry?.deletedLocally)); deletedOnServer: \(String(describing: fileEntry?.deletedOnServer)); url: \(String(describing: url)); nonRelativeURL: \(String(describing: nonRelativeURL))\n"
            }
        }
        
        return result
    }

    // Generate debugging information for pending deletions if any. Returns nil if none.
    public func debugPendingDeletions() throws -> String? {
        let deletionTrackers = try UploadDeletionTracker.fetch(db:db)
        guard deletionTrackers.count > 0 else {
            return nil
        }
        
        var result = ""
            
        for deletionTracker in deletionTrackers {
            result += "UploadDeletionTracker: uuid: \(deletionTracker.uuid); deletionType: \(deletionTracker.deletionType); status: \(deletionTracker.status);\n"
        }
        
        return result
    }
    
    // MARK: Sharing
    
    // The sharing groups in which the signed in user is a member, or was a member. If the user is no longer a member, the `deleted` property of the `iOSBasics.SharingGroup` is true. Note that for a specific sharing group, if a user is re-added to that sharing group, the `deleted` property can later (e.g., on another call to `sharingGroups()`) become true again.
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
    
    public enum MoveFileGroupsResult {
        case success
        
        // Not all of the v0 uploaders of the file groups given in the request were members of the target sharing group.
        case failedWithNotAllOwnersInTarget
        
        case failedWithUserConstraintNotSatisfied
        
        case currentUploads
        case currentDeletions
        
        case error(Error?)
    }
    
    /**
     * Fails if any uploads or deletions are currently occuring or
     * queued for the indicated file groups in the source sharing group.
     * (No uploads are allowed as I don't have an easy way to distinguish between
     * v0 and vN uploads-- I'd rather just disallow v0 uploads;
     * downloads are allowed as they should not be affected by a change in
     * sharing group for a file group).
     * On a successful completion, updates the local sharing groups of the
     * indicated file groups. And sends the push notification -- to the source
     * sharing group.
     * sourcePushNotificationMessage: A message to be sent to the source sharing group;
     * destinationPushNotificationMessage: A message to be sent to the destination sharing group;
     */
    public func moveFileGroups(_ fileGroups: [UUID], usersThatMustBeInDestination: Set<UserId>? = nil, fromSourceSharingGroup sourceSharingGroup: UUID, toDestinationSharingGroup destinationSharinGroup:UUID, sourcePushNotificationMessage: String? = nil, destinationPushNotificationMessage: String? = nil, completion:@escaping (MoveFileGroupsResult)->()) {
        serialQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                try self.moveFileGroupsHelper(fileGroups, usersThatMustBeInDestination: usersThatMustBeInDestination, fromSourceSharingGroup: sourceSharingGroup, toDestinationSharingGroup: destinationSharinGroup, sourcePushNotificationMessage: sourcePushNotificationMessage, destinationPushNotificationMessage: destinationPushNotificationMessage) { [weak self] result in
                    guard let self = self else { return }

                    self.dispatchQueue.async {
                        completion(result)
                    }
                }
            } catch let error {
                self.dispatchQueue.async {
                    completion(.error(error))
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
    
    /// On success, automatically syncs index before returning. `completion` returns SyncServerError.networkNotReachable if the network is not reachable. Only checks for network reachability (not app reachability) because this can be called when the app is just changing from background to foreground.
    public func redeemSharingInvitation(sharingInvitationUUID:UUID, emailAddress: String? = nil, completion: @escaping (Swift.Result<RedeemResult, Error>)->()) {

        guard requestable.canMakeNetworkRequests(options: .network) else {
            logger.info("Could not sync: Network not reachable")
            completion(.failure(SyncServerError.networkNotReachable))
            return
        }

        serialQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.api.redeemSharingInvitation(sharingInvitationUUID: sharingInvitationUUID, cloudFolderName: self.configuration.cloudFolderName, emailAddress: emailAddress) { [weak self] result in
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
    
        // Only considering the .network here because when this is typically called, the app is coming from the background to the foreground and using .app causes this to fail.
        guard requestable.canMakeNetworkRequests(options: [.network]) else {
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

