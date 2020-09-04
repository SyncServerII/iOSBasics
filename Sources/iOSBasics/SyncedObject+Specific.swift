//
//  File.swift
//  
//
//  Created by Christopher G Prince on 9/3/20.
//

import Foundation
import ServerShared

struct FileUpl: UploadableFile {
    let uuid: UUID
    let url: URL
    let persistence: LocalPersistence
}

struct FileDecl: FileDeclaration {
    let uuid: UUID
    let mimeType: MimeType
    let appMetaData: String?
    let changeResolverName: String?
}

class DeclObject: DeclaredObject {
    // An id for this SyncedObject. This is required because we're organizing SyncObject's around these UUID's. AKA, syncObjectId
    let fileGroupUUID: UUID
    
    // The type of object that this collection of files is representing.
    // E.g., a Neebla image or Neebla URL as above.
    let objectType: String

    // An id for the group of users that have access to this SyncedObject
    let sharingGroupUUID: UUID
    
    let declaredFiles: Set<FileDecl>
    
    init(fileGroupUUID: UUID, objectType: String, sharingGroupUUID: UUID, declaredFiles: Set<FileDecl>) {
        self.fileGroupUUID = fileGroupUUID
        self.objectType = objectType
        self.sharingGroupUUID = sharingGroupUUID
        self.declaredFiles = declaredFiles
    }
}
