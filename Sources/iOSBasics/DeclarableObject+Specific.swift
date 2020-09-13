//
//  DeclarableObject+Specific.swift
//  
//
//  Created by Christopher G Prince on 9/3/20.
//

import Foundation
import ServerShared

public struct FileUpload: UploadableFile {
    public let uuid: UUID
    public let dataSource: UploadDataSource
    
    public init(uuid: UUID, dataSource: UploadDataSource) {
        self.uuid = uuid
        self.dataSource = dataSource
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(uuid)
    }
}

public struct FileDeclaration: DeclarableFile {
    public let uuid: UUID
    public let mimeType: MimeType
    public let cloudStorageType: CloudStorageType
    public let appMetaData: String?
    public let changeResolverName: String?
    
    public init(uuid: UUID, mimeType: MimeType, cloudStorageType: CloudStorageType, appMetaData: String?, changeResolverName: String?) {
        self.uuid = uuid
        self.mimeType = mimeType
        self.cloudStorageType = cloudStorageType
        self.appMetaData = appMetaData
        self.changeResolverName = changeResolverName
    }
}

public struct ObjectDeclaration: DeclarableObject, Equatable {
    // An id for this SyncedObject. This is required because we're organizing SyncObject's around these UUID's. AKA, syncObjectId
    public let fileGroupUUID: UUID
    
    // The type of object that this collection of files is representing.
    // E.g., a Neebla image or Neebla URL as above. This is optional only to grandfather in early versions of Neebla. New object declarations must have this non-nil.
    public let objectType: String?

    // An id for the group of users that have access to this SyncedObject
    public let sharingGroupUUID: UUID
    
    public let declaredFiles: Set<FileDeclaration>
    
    public init(fileGroupUUID: UUID, objectType: String?, sharingGroupUUID: UUID, declaredFiles: Set<FileDeclaration>) {
        self.fileGroupUUID = fileGroupUUID
        self.objectType = objectType
        self.sharingGroupUUID = sharingGroupUUID
        self.declaredFiles = declaredFiles
    }
}

struct ObjectBasics: DeclarableObjectBasics {
    let fileGroupUUID: UUID
    let objectType: String?
    let sharingGroupUUID: UUID
}

public struct FileDownload: DownloadableFile {
    public let uuid: UUID
    public let fileVersion: FileVersionInt
    
    public init(uuid: UUID, fileVersion: FileVersionInt) {
        self.uuid = uuid
        self.fileVersion = fileVersion
    }
}
