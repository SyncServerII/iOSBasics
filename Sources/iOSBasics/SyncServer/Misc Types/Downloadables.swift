
import Foundation
import ServerShared

// A specification of a file that should be downloaded
public protocol DownloadableFile: File {
    var fileVersion: FileVersionInt { get }
}

public protocol DownloadableObject {
    associatedtype FileDownload: DownloadableFile
    var fileGroupUUID: UUID {get}
    var downloads: [FileDownload] {get}
}

// Indicates that the file needs to be downloaded
public protocol FileNeedingDownload: DownloadableFile {
    var fileVersion: FileVersionInt { get }
    var fileLabel: String { get }
}

public protocol ObjectNeedingDownload {
    associatedtype FileDownload: FileNeedingDownload
    var sharingGroupUUID: UUID {get}
    var fileGroupUUID: UUID {get}
    var creationDate: Date {get}
    var downloads: [FileDownload] {get}
}

public protocol FileWasDownloaded: DownloadableFile {
    var fileVersion: FileVersionInt { get }
    var fileLabel: String { get }
    var mimeType: MimeType { get }
    
    // Will be nil if this is v0 of file-- only has a creation date.
    var updateDate: Date? { get }
}

public protocol ObjectWasDownloaded {
    associatedtype FileDownload: FileWasDownloaded
    var sharingGroupUUID: UUID {get}
    var fileGroupUUID: UUID {get}
    var creationDate: Date {get}
    var downloads: [FileDownload] {get}
}

public protocol IndexableObject: ObjectNeedingDownload {
    var deleted: Bool {get}
    var objectType: String {get}
}

