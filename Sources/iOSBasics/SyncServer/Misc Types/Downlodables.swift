
import Foundation
import ServerShared

// A specification of a file that should be downloaded
public protocol FileShouldBeDownloaded: File {
    var fileVersion: FileVersionInt { get }
}

public protocol ObjectShouldBeDownloaded {
    associatedtype FileDownload: FileShouldBeDownloaded
    var fileGroupUUID: UUID {get}
    var downloads: [FileDownload] {get}
}

// Indicates that the file needs to be downloaded
public protocol FileNeedingDownload: FileShouldBeDownloaded {
    var fileVersion: FileVersionInt { get }
    var fileLabel: String { get }
}

public protocol ObjectNeedingDownload {
    associatedtype FileDownload: FileNeedingDownload
    var fileGroupUUID: UUID {get}
    var downloads: [FileDownload] {get}
}
