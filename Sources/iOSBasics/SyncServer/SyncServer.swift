import Foundation
import SQLite
import iOSShared
import ServerShared
import iOSSignIn

public class SyncServer {
    private let configuration: Configuration
    weak var delegate: SyncServerDelegate?
    let db: Connection
    var signIns: SignIns!
    let hashingManager: HashingManager
    private(set) var api:ServerAPI!
    
    public init(hashingManager: HashingManager,
        db:Connection,
        configuration: Configuration,
        delegate: SyncServerDelegate) throws {
        self.configuration = configuration
        self.db = db
        self.hashingManager = hashingManager
        
        try Database.setup(db: db)
        let config = Networking.Configuration(temporaryFileDirectory: Files.getDocumentsDirectory(), temporaryFilePrefix: "SyncServer", temporaryFileExtension: "dat", baseURL: configuration.serverURL.absoluteString, minimumServerVersion: nil)
        api = ServerAPI(database: db, hashingManager: hashingManager, delegate: self, config: config)
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
    
    public func sync() {
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

extension SyncServer: ServerAPIDelegate {
    func hasher(_ delegated: AnyObject, forCloudStorageType cloudStorageType: CloudStorageType) throws -> CloudStorageHashing {
        var hashing: CloudStorageHashing!
        return hashing
    }
    
    func credentialsForNetworkRequests(_ delegated: AnyObject) -> GenericCredentials {
        var creds: GenericCredentials!
        return creds
    }
    
    func deviceUUID(_ delegated: AnyObject) -> UUID {
        return UUID()
    }
    
    func uploadCompleted(_ delegated: AnyObject, result: Swift.Result<UploadFileResult, Error>) {
    
    }
    func downloadCompleted(_ delegated: AnyObject, result: Swift.Result<DownloadFileResult, Error>) {
    
    }
}
