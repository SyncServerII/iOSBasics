import Foundation

public class SyncServer {
    private let configuration: Configuration
    weak var delegate: SyncServerDelegate?
    
    public init(configuration: Configuration, delegate: SyncServerDelegate) {
        self.configuration = configuration
    }
    
    // MARK: Persistent queuing for upload

    public func getAttributes(forFileUUID fileUUID: UUID) {
    }
    
    // Get list of pending downloads, and if no conflicting uploads, do these uploads.
    // If there are conflicting uploads, the downloads will need to be manually started first (see methods below) and then sync retried.
    // Uploads are done on a background networking URLSession.
    public func queue(object: SyncedObject) {
    }
    
    public func uploadAppMetaData(file: UUID) {
    }
    
    // TODO: I think a deletion needs to be on an entire SyncedObject basis.
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
    
    // MARK: Reset
    
    public func reset() {
    
    }
    
    // MARK: Migration support.
    
    public func importFiles(files: [UUID]) {
    }
}
