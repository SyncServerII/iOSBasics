
import Foundation
import ServerShared

// Enable previously registered and downloaded DeclarableObjects to be handled. i.e., handles downloads for specific objectType's.
public protocol ObjectDownloadHandler {
    // Helper to deal with older version objects that don't have explicit fileLabel's
    func getFileLabel(appMetaData: String) -> String?
    
    // Gets called in an async manner by iOSBasics
    func objectWasDownloaded(object: DownloadedObject) throws
}

extension FileInfo {
    // Just returns a fileLabel as long as it exists; no specific validity checking on the file label is done.
    func getFileLabel(objectType: String, objectDeclarations:[String: ObjectDownloadHandler]) throws -> String {
        if let fileLabel = fileLabel {
            return fileLabel
        } else if let appMetaData = appMetaData,
            let type = objectDeclarations[objectType],
            let fileLabel = type.getFileLabel(appMetaData: appMetaData) {
            return fileLabel
        }
        else {
            throw SyncServerError.internalError("No fileLabel")
        }
    }
}

