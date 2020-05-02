import Foundation

public class SyncServer {
    private let configuration: Configuration
    weak var delegate: SyncServerDelegate?
    
    public init(configuration: Configuration, delegate: SyncServerDelegate) {
        self.configuration = configuration
    }
    
    // MARK: Persistent queuing for upload

    public enum FilePersistence {
        case copy
        case immutable
    }
    
    public struct FileAttributes: Equatable {
        let uuid: UUID
        let sharingGroup: UUID
    }
    
    public struct File: Hashable {
        let url: URL
        let filePersistence: FilePersistence
        let attributes: FileAttributes
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(attributes.uuid)
        }
    }
    
    // Get list of pending downloads, and if no conflicting uploads, do these uploads.
    // If there are conflicting uploads, the downloads will need to be manually started first (see methods below) and then sync retried.
    // Uploads are done on a background networking URLSession.
    // If more than one file queued, they must have the the same sharing group.
    public func queue(files: Set<File>) {
    }
    
    public func uploadAppMetaData(attributes: FileAttributes) {
    }
    
    public func delete(fileWith uuid:UUID) {
    }
    
    public func delete(filesWith uuids:[UUID]) {
    }
    
    public func createSharingGroup(sharingGroup: UUID, sharingGroupName: String? = nil) {
    }
    
    public func updateSharingGroup(sharingGroup: UUID, newSharingGroupName: String) {
    }
    
    // Remove the current user (indicated in the Configuration) from the sharing group.
    public func removeFromSharingGroup(sharingGroup: UUID) {
    }
    
    // MARK: Synchronization
    
    public func sync() {
    }
    
    // MARK: Download
    
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
    
    // MARK: Migration support.
    
    public func importFiles(files: [FileAttributes]) {
    }
}
