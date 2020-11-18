
import Foundation
import ServerShared

// Enable previously registered and downloaded DeclarableObjects to be handled. i.e., handles downloads for specific objectType's.
public protocol ObjectDownloadHandler {
    // Helper to deal with older version objects that don't have explicit fileLabel's
    func getFileLabel(appMetaData: String) -> String?
    
    func objectWasDownloaded(object: DownloadedObject) throws
}

extension FileInfo {
    func getFileLabel(objectType: String, objectDeclarations:[String: ObjectDownloadHandler]) throws -> String {
        if let fileLabel = fileLabel {
            return fileLabel
        } else if let appMetData = appMetaData,
            let type = objectDeclarations[objectType],
            let fileLabel = type.getFileLabel(appMetaData: appMetData) {
            return fileLabel
        }
        else {
            throw SyncServerError.internalError("No fileLabel")
        }
    }
}

