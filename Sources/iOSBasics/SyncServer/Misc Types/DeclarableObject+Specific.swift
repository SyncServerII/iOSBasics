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
    public let mimeTypes: Set<MimeType>
    public let changeResolverName: String?
    
    public init(fileLabel: String, mimeTypes: Set<MimeType>, changeResolverName: String?) {
        self.fileLabel = fileLabel
        self.mimeTypes = mimeTypes
        self.changeResolverName = changeResolverName
    }
    
    public static func == (lhs: FileDeclaration, rhs: FileInfo) -> Bool {
        // Not including fileLabel in comparison because fileLabel can be nil in FileInfo.
        var mimeTypeFactor = true
        if let rhsMimeType = rhs.mimeType {
            let mimeTypeStrings:Set<String> = Set(lhs.mimeTypes.map {$0.rawValue})
            mimeTypeFactor = mimeTypeStrings.contains(rhsMimeType)
        }
        
        return mimeTypeFactor &&
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

public struct DownloadFile: FileNeedingDownload {
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

public struct NotDownloadedFile: FileNotDownloaded {
    public let uuid: UUID
    
    public init(uuid: UUID) {
        self.uuid = uuid
    }
}

public struct DownloadObject: ObjectNeedingDownload {
    public let sharingGroupUUID: UUID
    public let fileGroupUUID: UUID
    public let creationDate: Date
    
    public let downloads: [DownloadFile]
    
    public init(sharingGroupUUID: UUID, fileGroupUUID: UUID, creationDate: Date, downloads: [DownloadFile]) {
        self.sharingGroupUUID = sharingGroupUUID
        self.fileGroupUUID = fileGroupUUID
        self.creationDate = creationDate
        self.downloads = downloads
    }
}

public struct NotDownloadedObject: ObjectNotDownloaded {
    public let sharingGroupUUID: UUID
    public let fileGroupUUID: UUID
    
    public let downloads: [NotDownloadedFile]
    
    public init(sharingGroupUUID: UUID, fileGroupUUID: UUID, downloads: [NotDownloadedFile]) {
        self.sharingGroupUUID = sharingGroupUUID
        self.fileGroupUUID = fileGroupUUID
        self.downloads = downloads
    }
}

public struct IndexObject: IndexableObject {
    public let deleted: Bool
    public let objectType: String
    public let sharingGroupUUID: UUID
    public let fileGroupUUID: UUID
    public let creationDate: Date
    
    // This is the most recent update date of any file in the object.
    public let updateDate: Date?
    
    public let downloads: [DownloadFile]
    
    public init(sharingGroupUUID: UUID, fileGroupUUID: UUID, objectType: String, creationDate: Date, updateDate: Date?, deleted: Bool, downloads: [DownloadFile]) {
        self.sharingGroupUUID = sharingGroupUUID
        self.fileGroupUUID = fileGroupUUID
        self.creationDate = creationDate
        self.updateDate = updateDate
        self.downloads = downloads
        self.deleted = deleted
        self.objectType = objectType
    }
}

public struct DownloadedFile: FileWasDownloaded {
    public let uuid: UUID
    public let fileVersion: FileVersionInt
    public let fileLabel: String
    public let mimeType: MimeType
    public let updateDate: Date?
    public let appMetaData: String?
    
    public enum Contents {
        case gone(GoneReason)
        
        // When returned to the client, this file needs to be moved or copied to a client location for persistence.
        case download(URL)
    }
    
    public let contents: Contents
    
    public init(uuid: UUID, fileVersion: FileVersionInt, fileLabel: String, mimeType: MimeType, updateDate: Date?, appMetaData: String?, contents: DownloadedFile.Contents) {
        self.uuid = uuid
        self.fileVersion = fileVersion
        self.fileLabel = fileLabel
        self.mimeType = mimeType
        self.contents = contents
        self.updateDate = updateDate
        self.appMetaData = appMetaData
    }
}

public struct DownloadedObject: ObjectWasDownloaded {
    public let creationDate: Date
    
    // Has a sharingGroupUUID because `DownloadedObject` is used in the `ObjectDownloadHandler` `objectWasDownloaded` method and that method needs to know the sharing group.
    public let sharingGroupUUID: UUID
    
    public let fileGroupUUID: UUID
    public let downloads: [DownloadedFile]
    
    public init(sharingGroupUUID: UUID, fileGroupUUID: UUID, creationDate: Date, downloads: [DownloadedFile]) {
        self.sharingGroupUUID = sharingGroupUUID
        self.fileGroupUUID = fileGroupUUID
        self.creationDate = creationDate
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
