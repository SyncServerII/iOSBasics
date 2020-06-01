import Foundation
import SQLite
import iOSShared

public class SyncServer {
    private let configuration: Configuration
    weak var delegate: SyncServerDelegate?
    let database: Connection
    var signIns: SignIns!
    let hashingManager: HashingManager
    var api:ServerAPI!
    
    public init(hashingManager: HashingManager,
        configuration: Configuration,
        delegate: SyncServerDelegate) throws {
        self.configuration = configuration
        self.database = try Connection(configuration.sqliteDatabasePath)
        self.hashingManager = hashingManager
        assert(false)
        //let networkingConfig = Networking.Configuration(temporaryFileDirectory: <#T##URL#>, temporaryFilePrefix: <#T##String#>, temporaryFileExtension: <#T##String#>, baseURL: <#T##String#>, minimumServerVersion: <#T##Version?#>)
        //let api = ServerAPI(database: database, hashingManager: hashingManager, delegate: self, config: Networking.Configuration)
    }
    
    // MARK: Persistent queuing for upload
    
    // Get list of pending downloads, and if no conflicting uploads, do these uploads.
    // If there are conflicting uploads, the downloads will need to be manually started first (see methods below) and then sync retried.
    // Uploads are done on a background networking URLSession.
    // If you upload an object that has a fileGroupUUID which is already queued or in progress of uploading, your request will be queued.
    public func queue(object: SyncedObject) throws {
        try queueObject(object)
    }
    
    public func sync() {
    }
    
    // MARK: Unqueued requests-- these will fail if they involve a file or other object currently queued for upload.
    
    public func uploadAppMetaData(file: UUID) {
    }
    
    public func delete(object: SyncedObject) {
    }
    
    public func createSharingGroup(sharingGroup: UUID, sharingGroupName: String? = nil) {
    }
    
    public func updateSharingGroup(sharingGroup: UUID, newSharingGroupName: String) {
    }
    
    // Remove the current user from the sharing group.
    public func removeFromSharingGroup(sharingGroup: UUID) {
    }
    
    // MARK: Download
    
    // The list of files returned here survive app relaunch.
    func filesNeedingDownload() -> [UUID] {
        return []
    }
    
    // Conflict resolution methods are applied automatically when files are downloaded, if there are conflicting pending uploads. See the Configuration.
    // This method is typically used to trigger downloads of files indicated in filesNeedingDownload, but it can also be used to trigger downloads independently of that.
    func startDownload(file: UUID) {
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
