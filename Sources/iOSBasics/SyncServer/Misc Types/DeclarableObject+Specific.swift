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
        // Not including fileLabel in comparison because fileLabel can be nil in FileInfo.
        return lhs.mimeType.rawValue == rhs.mimeType &&
            lhs.changeResolverName == rhs.changeResolverName
    }
}

public struct FileToDownload: DownloadableFile {
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

public struct ObjectToDownload: DownloadableObject {
    public let fileGroupUUID: UUID
    public let downloads: [FileToDownload]
    
    public init(fileGroupUUID: UUID, downloads: [FileDownload]) {
        self.fileGroupUUID = fileGroupUUID
        self.downloads = downloads
    }
}

public struct DownloadFile: DownloadingFile {
    public let uuid: UUID
    public let fileVersion: FileVersionInt
    public let fileLabel: String
    
    public init(uuid: UUID, fileVersion: FileVersionInt, fileLabel: String) {
        self.uuid = uuid
        self.fileVersion = fileVersion
        self.fileLabel = fileLabel
    }

    public static func ==(lhs: DownloadFile, rhs: DownloadFile) -> Bool {
        return lhs.fileLabel == rhs.fileLabel &&
            lhs.uuid == rhs.uuid
    }

    public static func ==(lhs: DownloadFile, rhs: UploadableFile) -> Bool {
        return lhs.fileLabel == rhs.fileLabel &&
            lhs.uuid == rhs.uuid
    }
}

public struct DownloadObject: DownloadingObject {
    public let fileGroupUUID: UUID
    public let downloads: [DownloadFile]
    
    public init(fileGroupUUID: UUID, downloads: [DownloadFile]) {
        self.fileGroupUUID = fileGroupUUID
        self.downloads = downloads
    }
}

public struct DownloadedFile: DownloadingFile {
    public let uuid: UUID
    public let fileVersion: FileVersionInt
    public let fileLabel: String
    
    public enum Contents {
        case gone
        case download(URL)
    }
    
    public let contents: Contents
    
    public init(uuid: UUID, fileVersion: FileVersionInt, fileLabel: String, contents: DownloadedFile.Contents) {
        self.uuid = uuid
        self.fileVersion = fileVersion
        self.fileLabel = fileLabel
        self.contents = contents
    }
}

public struct DownloadedObject: DownloadingObject {
    public let fileGroupUUID: UUID
    public let downloads: [DownloadedFile]
    
    public init(fileGroupUUID: UUID, downloads: [DownloadedFile]) {
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
