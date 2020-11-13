
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
    var fileGroupUUID: UUID {get}
    var downloads: [FileDownload] {get}
}