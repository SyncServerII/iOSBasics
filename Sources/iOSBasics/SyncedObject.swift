import Foundation
import ServerShared

public enum LocalPersistence {
    case copy
    case immutable
    
    var isCopy: Bool {
        return self == .copy
    }
}

public protocol File: Hashable {
    var uuid: UUID {get}
}

public protocol FileDeclaration: File {
    var mimeType: MimeType {get}
    var appMetaData: String? {get}

    // If the file will be changed and have multiple versions on the server, this must be non-nil and a valid change resolver name. For a static file that will not be changed beyond v0 of the file on the server, this must be nil.
    var changeResolverName: String? {get}
}

public protocol UploadableFile: File {
    var url: URL {get}
    var persistence: LocalPersistence {get}
}

public protocol DeclaredObject {
    associatedtype DeclaredFile: FileDeclaration

    // An id for this SyncedObject. This is required because we're organizing SyncObject's around these UUID's. AKA, syncObjectId
    var fileGroupUUID: UUID { get }
    
    // The type of object that this collection of files is representing.
    // E.g., a Neebla image or Neebla URL as above.
    var objectType: String { get }

    // An id for the group of users that have access to this SyncedObject
    var sharingGroup: UUID { get }
    
    var declaredFiles: Set<DeclaredFile> { get }
}

extension DeclaredObject {
    var syncObjectId: UUID {
        return fileGroupUUID
    }
}
    
/* An abstraction of a data object backed by one or more cloud storage files. Two examples from Neebla:

1) An image: Represented by a (a) jpg image file and (b) a discussion thread file.
2) A website: Represented by (a) an optional jpg file for an image depicting the URL website contents, (b) a file containing the URL for the website, and (c) a discussion thread file.

Representations in terms of a set of files are selected both in terms of the need for storing information for an application's data object, and in terms of having representations that are basically intelligible to a user when stored in their cloud storage. For example, it wouldn't be suitable to compress data files in a non-obvious encoding. JPEG format is fine as it's widely used, and zip compression could be fine as well. But a proprietary compression algorithm not widely used would not be suitable.
*/
public protocol SyncedObject: DeclaredObject {
    associatedtype UploadFile: UploadableFile
    var uploads: Set<UploadFile> { get }
}

