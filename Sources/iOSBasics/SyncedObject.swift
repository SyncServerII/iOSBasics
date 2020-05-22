import Foundation
import ServerShared

public enum Persistence {
    case copy
    case immutable
}

public struct File: Hashable {
    let uuid: UUID
    let url: URL
    let mimeType: MimeType
    let persistence: Persistence
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(uuid)
    }
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.uuid == rhs.uuid
    }
}
    
/* An abstraction of a data object backed by one or more files. Two examples from Neebla:

1) An image: Represented by a jpg file and a discussion thread file.
2) A website: Represented by an optional jpg file for an image depicting the URL website contents, a file containing the URL for the website, and a discussion thread file.

Representations in terms of a set of files are selected both in terms of the need for storing information for an application's data object, and in terms of having representations that are basically intelligible to a user when stored in their cloud storage. For example, it wouldn't be suitable to compress data files in a non-obvious encoding. JPEG format is fine as it's widely used, and zip compression could be fine as well. But a proprietary compression algorithm not widely used would not be suitable.
*/

public protocol SyncedObject {
    // The type of object that this collection of files is representing.
    var objectType: String { get }

    // An id for the group of users that have access to this SyncedObject
    var sharingGroup: UUID { get }
    
    // An id for this SyncedObject (maps to a fileGroupUUID on the server)
    var objectUUID: UUID { get }
    
    // The collection of files that represent this SyncedObject
    var files: Set<File> { get }
    
    func resolveConflict(f1: File, f2: File)
}
