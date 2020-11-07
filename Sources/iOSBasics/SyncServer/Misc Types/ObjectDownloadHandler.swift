
import Foundation

// Enable previously registered and downloaded DeclarableObjects to be handled.

public protocol ObjectDownloadHandler {
    // Helpers to deal with older version objects that don't have explicit objectType's / fileLabel's
    func getObjectType(appMetaData: String) throws -> String
    func getFileLabel(appMetaData: String) throws -> String
    
    func objectWasDownloaded(object: DownloadObject)
}
