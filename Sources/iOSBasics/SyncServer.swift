import Foundation

public class SyncServer {
    private let configuration: Configuration
    weak var delegate: SyncServerDelegate?
    
    public init(configuration: Configuration, delegate: SyncServerDelegate) {
        self.configuration = configuration
    }
    
    // MARK: Persistent queuing for upload
    
    public func queueCopy(file: FileAttributes) {
    }
    
    public func queueImmutable(file: FileAttributes) {
    }
    
    public func uploadAppMetaData(file: FileAttributes) {
    }
    
    public func delete(fileWithUUID uuid:UUID) {
    }
    
    public func delete(filesWithUUIDs uuids:[UUID]) {
    }
    
    public func createSharingGroup(sharingGroupUUID: String, sharingGroupName: String? = nil) {
    }
    
    public func updateSharingGroup(sharingGroupUUID: String, newSharingGroupName: String) {
    }
    
    public func removeFromSharingGroup(sharingGroupUUID: String) {
    }
    
    // MARK: Synchronization
    
    // Get list of pending downloads, and if no conflicting uploads, do those uploads if any.
    // If there are conflicting uploads, the downloads will need to be manually started first (see methods below) and then this sync retried.
    // Uploads are done on a background networking URLSession.
    public func sync() {
    }
    
    // MARK: Download
    
    public struct FileAttributes {
    }
    
    // The list of files returned here survive app relaunch.
    func filesNeedingDownload() -> [FileAttributes] {
        return []
    }
    
    // Conflict resolution methods are applied automatically when files are downloaded, if there are conflicting pending uploads. See the Configuration.
    func startDownload(attributes: FileAttributes) {
    }
    
    // MARK: Information operations
    
    public struct SharingGroup {
    }
    
    public var sharingGroups: [SharingGroup] {
        return []
    }
    
    public func getAttributes(forFileUUID fileUUID: UUID) {
    }
    
    // MARK: Reset
    
    public func reset() {
    
    }
}
