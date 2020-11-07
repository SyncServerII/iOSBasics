//
//  DeclarableObject+Specific.swift
//  
//
//  Created by Christopher G Prince on 9/3/20.
//

import Foundation
import ServerShared

public struct FileDeclaration: DeclarableFile, Codable, Hashable {
    public var fileLabel: String
    public let mimeType: MimeType
    public let changeResolverName: String?
    
    public init(fileLabel: String, mimeType: MimeType, changeResolverName: String?) {
        self.fileLabel = fileLabel
        self.mimeType = mimeType
        self.changeResolverName = changeResolverName
    }
    
    public static func == (lhs: FileDeclaration, rhs: FileInfo) -> Bool {
        return lhs.fileLabel == rhs.fileLabel &&
            lhs.mimeType.rawValue == rhs.mimeType &&
            lhs.changeResolverName == rhs.changeResolverName
    }
}

/*
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
    public let appMetaData: String?
    public let changeResolverName: String?
    
    public init(uuid: UUID, mimeType: MimeType, appMetaData: String?, changeResolverName: String?) {
        self.uuid = uuid
        self.mimeType = mimeType
        self.appMetaData = appMetaData
        self.changeResolverName = changeResolverName
    }
}

struct ObjectBasics: DeclarableObjectBasics {
    let fileGroupUUID: UUID
    let objectType: String?
    let sharingGroupUUID: UUID
}
*/

public struct FileToDownload: FileShouldBeDownloaded {
    public let uuid: UUID
    public let fileVersion: FileVersionInt
    
    public init(uuid: UUID, fileVersion: FileVersionInt) {
        self.uuid = uuid
        self.fileVersion = fileVersion
    }

    public static func ==(lhs: FileToDownload, rhs: FileToDownload) -> Bool {
        return lhs.uuid == rhs.uuid &&
            lhs.fileVersion == rhs.fileVersion
    }
}

public struct ObjectToDownload: ObjectShouldBeDownloaded {
    public let fileGroupUUID: UUID
    public let downloads: [FileToDownload]
    
    public init(fileGroupUUID: UUID, downloads: [FileDownload]) {
        self.fileGroupUUID = fileGroupUUID
        self.downloads = downloads
    }
}

public struct FileNeedsDownload: FileNeedingDownload {
    public let uuid: UUID
    public let fileVersion: FileVersionInt
    public let fileLabel: String
    
    public init(uuid: UUID, fileVersion: FileVersionInt, fileLabel: String) {
        self.uuid = uuid
        self.fileVersion = fileVersion
        self.fileLabel = fileLabel
    }

    public static func ==(lhs: FileNeedsDownload, rhs: FileNeedsDownload) -> Bool {
        return lhs.fileLabel == rhs.fileLabel &&
            lhs.uuid == rhs.uuid
    }

    public static func ==(lhs: FileNeedsDownload, rhs: UploadableFile) -> Bool {
        return lhs.fileLabel == rhs.fileLabel &&
            lhs.uuid == rhs.uuid
    }
}

public struct ObjectNeedsDownload: ObjectNeedingDownload {
    public let fileGroupUUID: UUID
    public let downloads: [FileNeedsDownload]
    
    public init(fileGroupUUID: UUID, downloads: [FileNeedsDownload]) {
        self.fileGroupUUID = fileGroupUUID
        self.downloads = downloads
    }
}

public struct ObjectDeclaration: DeclarableObject {
    // The type of object that this collection of files is representing.
    // E.g., a Neebla image or Neebla URL as above. This is optional only to grandfather in early versions of Neebla. New object declarations must have this non-nil.
    public let objectType: String
    
    public var declaredFiles: [DeclarableFile]
    
    public init(objectType: String, declaredFiles: [DeclarableFile]) {
        self.objectType = objectType
        self.declaredFiles = declaredFiles
    }
}
