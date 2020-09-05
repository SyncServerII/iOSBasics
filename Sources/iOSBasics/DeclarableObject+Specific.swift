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
    public let url: URL
    public let persistence: LocalPersistence
    
    public init(uuid: UUID, url: URL, persistence: LocalPersistence) {
        self.uuid = uuid
        self.url = url
        self.persistence = persistence
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

public struct ObjectDeclaration: DeclarableObject {
    // An id for this SyncedObject. This is required because we're organizing SyncObject's around these UUID's. AKA, syncObjectId
    public let fileGroupUUID: UUID
    
    // The type of object that this collection of files is representing.
    // E.g., a Neebla image or Neebla URL as above.
    public let objectType: String

    // An id for the group of users that have access to this SyncedObject
    public let sharingGroupUUID: UUID
    
    public let declaredFiles: Set<FileDeclaration>
    
    public init(fileGroupUUID: UUID, objectType: String, sharingGroupUUID: UUID, declaredFiles: Set<FileDeclaration>) {
        self.fileGroupUUID = fileGroupUUID
        self.objectType = objectType
        self.sharingGroupUUID = sharingGroupUUID
        self.declaredFiles = declaredFiles
    }
}
