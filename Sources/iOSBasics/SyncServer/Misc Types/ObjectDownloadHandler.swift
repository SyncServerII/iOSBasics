
import Foundation

// Enable previously registered and downloaded DeclarableObjects to be handled.

public protocol ObjectDownloadHandler {
    // A helper to deal with older version objects that don't have explicit objectType's.
    func getObjectType(appMetaData: String) throws -> String
    
    func getFileLabel(appMetaData: String) throws -> String
    
    func objectWasDownloaded(object: DeclarableObject)
}
