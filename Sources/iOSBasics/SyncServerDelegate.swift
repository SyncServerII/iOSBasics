import Foundation
import iOSSignIn
import ServerShared
import Version

public enum UUIDCollisionType {
    case file
    case fileGroup
    case sharingGroup
    case device
}

public protocol SyncServerCredentials: AnyObject {
    // This method may be called by the SyncServer using *any* queue.
    func credentialsForServerRequests(_ syncServer: SyncServer) throws -> GenericCredentials
}

public protocol SyncServerHelpers: AnyObject {
    // For older objects, maps appMetaData to objectType
    func objectType(_ caller: AnyObject, forAppMetaData appMetaData: String) -> String?
}

extension SyncServerHelpers {
    func getObjectType(file: FileInfo) throws -> String {
        // If a fileIndex fileUUID has a DirectoryFileEntry or a DirectoryObjectEntry then their main (static) components must not have changed.
        if let objectType = file.objectType {
            return objectType
        }
        else if let appMetaData = file.appMetaData,
            let objectType = objectType(self, forAppMetaData: appMetaData) {
            return objectType
        }
        else {
            throw SyncServerError.internalError("No object type!")
        }
    }
}

public enum SyncResult {
    case noIndex
    case index(sharingGroupUUID: UUID, index: [IndexObject])
}

public enum DeferredOperation {
    case upload
    case deletion
}

public struct UploadResult {
    public enum UploadType {
        case gone
        case success
    }
    
    let fileUUID: UUID
    let uploadType: UploadType
    
    public init(fileUUID: UUID, uploadType: UploadType) {
        self.fileUUID = fileUUID
        self.uploadType = uploadType
    }
}

public struct DownloadResult {
    public enum DownloadType {
        case gone
        case success(localFile: URL)
    }
    
    let fileUUID: UUID
    let downloadType: DownloadType
    
    public init(fileUUID: UUID, downloadType: DownloadType) {
        self.fileUUID = fileUUID
        self.downloadType = downloadType
    }
}

public enum DownloadDeletion {
    case file(UUID)
    case fileGroup(UUID)
}

public enum DownloadEvent {
    // The `queue` method was called, but the download couldn't be done immediately. It was queued for download later instead.
    case queued(fileGroupUUID: UUID)
    
    case completed(DownloadResult)
    
    // Called after a successful sync.
    case sync(numberDownloadsStarted: UInt)
}

public enum UploadEvent {
    // The `queue` method was called, but the upload couldn't be done immediately. It was queued for upload later instead.
    case queued(fileGroupUUID: UUID)
    
    // Upload started successfully. Request was sent to server.
    case started
    
    // Request to server for an upload completed successfully.
    case completed(UploadResult)
}

public enum UserEvent {
    case error(Error?)
    
    // Client of SyncServer should show show user an alert
    case showAlert(title: String, message: String)
}

public enum BadVersion {
    case badServerVersion(Version?)
    case badClientAppVersion(minimumNeeded: Version)
}

// These methods are all called on the `delegateDispatchQueue` passed to the SyncServer constructor.
public protocol SyncServerDelegate: AnyObject {
    // The server version is bad. Likely the iOS app needs upgrading.
    func badVersion(_ syncServer: SyncServer, version: BadVersion)

    // These probably need to be shown to the user.
    func userEvent(_ syncServer: SyncServer, event: UserEvent)
    
    // Called after the `sync` method is successful. If nil sharing group was given, the result is .noResult. If non-nil sharing group, the index is given.
    func syncCompleted(_ syncServer: SyncServer, result: SyncResult)
    
    // A uuid that was initially generated on the client 
    func uuidCollision(_ syncServer: SyncServer, type: UUIDCollisionType, from: UUID, to: UUID)
    
    // The rest have informative detail; perhaps purely for testing.
    
    func uploadQueue(_ syncServer: SyncServer, event: UploadEvent)
    func downloadQueue(_ syncServer: SyncServer, event: DownloadEvent)
    
    func objectMarkedAsDownloaded(_ syncServer: SyncServer, fileGroupUUID: UUID)

    // Request to server for upload deletion completed successfully.
    func deletionCompleted(_ syncServer: SyncServer, forObjectWith fileGroupUUID: UUID)

    // Called when vN deferred upload(s), or deferred deletions, successfully completed, is/are detected.
    func deferredCompleted(_ syncServer: SyncServer, operation: DeferredOperation, numberCompleted: Int)
    
    // Another client deleted a file/file group.
    func downloadDeletion(_ syncServer: SyncServer, details: DownloadDeletion)
}
