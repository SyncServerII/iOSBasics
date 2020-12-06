
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
public protocol DownloadingFile: DownloadableFile {
    var fileVersion: FileVersionInt { get }
    var fileLabel: String { get }
}

public protocol DownloadingObject {
    associatedtype FileDownload: DownloadingFile
    var sharingGroupUUID: UUID {get}
    var fileGroupUUID: UUID {get}
    var creationDate: Date {get}
    var downloads: [FileDownload] {get}
}

public protocol IndexableObject: DownloadingObject {
    var deleted: Bool {get}
    var objectType: String {get}
}

