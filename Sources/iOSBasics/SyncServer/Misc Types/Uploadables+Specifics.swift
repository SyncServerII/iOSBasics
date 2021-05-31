
import Foundation
import ServerShared

public struct FileUpload: UploadableFile {
    public let fileLabel: String
    public let mimeType: MimeType?
    public let dataSource: UploadDataSource
    public let uuid: UUID
    public let appMetaData: String?
    public let informAllButSelf: Bool?
    
    public init(fileLabel: String, mimeType: MimeType? = nil, dataSource: UploadDataSource, uuid: UUID, appMetaData: String? = nil, informAllButSelf: Bool? = nil) {
        self.fileLabel = fileLabel
        self.mimeType = mimeType
        self.dataSource = dataSource
        self.uuid = uuid
        self.appMetaData = appMetaData
        self.informAllButSelf = informAllButSelf
    }
}

public struct ObjectUpload: UploadableObject {
    public let pushNotificationMessage: String?

    public let objectType: String
    
    // This identifies the specific object instance.
    public let fileGroupUUID: UUID
    
    public let sharingGroupUUID: UUID
    public let uploads: [UploadableFile]
    
    public init(objectType: String, fileGroupUUID: UUID, sharingGroupUUID: UUID, pushNotificationMessage: String? = nil, uploads: [UploadableFile]) {
        self.objectType = objectType
        self.fileGroupUUID = fileGroupUUID
        self.sharingGroupUUID = sharingGroupUUID
        self.uploads = uploads
        self.pushNotificationMessage = pushNotificationMessage
    }
    
    public static func ==(lhs: ObjectUpload, rhs: DownloadObject) -> Bool {
        guard lhs.uploads.count == rhs.downloads.count else {
            return false
        }
        
        // Sort the uploads and downloads to get them in cannonical order.
        let uploads = lhs.uploads.sorted { (f1, f2) -> Bool in
            return f1.fileLabel < f2.fileLabel
        }
        
        let downloads = rhs.downloads.sorted { (f1, f2) -> Bool in
            return f1.fileLabel < f2.fileLabel
        }
        
        for (upload, download) in zip(uploads, downloads) {
            guard download == upload else {
                return false
            }
        }
        
        return lhs.fileGroupUUID == rhs.fileGroupUUID
    }
}
