
import Foundation

public struct FileUpload: UploadableFile {
    public let fileLabel: String
    public let dataSource: UploadDataSource
    public let uuid: UUID
    public let appMetaData: String?
    
    public init(fileLabel: String, dataSource: UploadDataSource, uuid: UUID, appMetaData: String? = nil) {
        self.fileLabel = fileLabel
        self.dataSource = dataSource
        self.uuid = uuid
        self.appMetaData = appMetaData
    }
}

public struct ObjectUpload: UploadableObject {    
    public let objectType: String
    
    // This identifies the specific object instance.
    public let fileGroupUUID: UUID
    
    public let sharingGroupUUID: UUID
    public let uploads: [UploadableFile]
}
