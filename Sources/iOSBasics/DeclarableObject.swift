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

public extension File {
    static func hasDistinctUUIDs(in set: Set<Self>) -> Bool {
        let uuids = Set<UUID>(set.map {$0.uuid})
        return uuids.count == set.count
    }
}

public protocol DeclarableFile: File {
    var mimeType: MimeType {get}
    var appMetaData: String? {get}

    // If the file will be changed and have multiple versions on the server, this must be non-nil and a valid change resolver name. For a static file that will not be changed beyond v0 of the file on the server, this must be nil.
    var changeResolverName: String? {get}
}

public extension DeclarableFile {
    func compare<FILE: DeclarableFile>(to other: FILE) -> Bool {
        return self.uuid == other.uuid &&
            self.mimeType == other.mimeType &&
            self.appMetaData == other.appMetaData &&
            self.changeResolverName == other.changeResolverName
    }
    
    static func compare<FILE1: DeclarableFile, FILE2: DeclarableFile>(
        first: Set<FILE1>, second: Set<FILE2>) -> Bool {
        let firstUUIDs = Set<UUID>(first.map { $0.uuid })
        let secondUUIDs = Set<UUID>(second.map { $0.uuid })
        
        guard firstUUIDs == secondUUIDs else {
            return false
        }
        
        for uuid in firstUUIDs {
            guard let a = first.first(where: {$0.uuid == uuid}),
                let b = second.first(where: {$0.uuid == uuid}) else {
                return false
            }
            
            return a.compare(to: b)
        }
        
        return true
    }
}

public protocol UploadableFile: File {
    var url: URL {get}
    var persistence: LocalPersistence {get}
}

extension UploadableFile {
    public func compare<FILE: UploadableFile>(to other: FILE) -> Bool {
        return self.uuid == other.uuid &&
            self.url == other.url &&
            self.persistence == other.persistence
    }
    
    public static func compare<FILE1: UploadableFile, FILE2: UploadableFile>(
        first: Set<FILE1>, second: Set<FILE2>) -> Bool {
        let firstUUIDs = Set<UUID>(first.map { $0.uuid })
        let secondUUIDs = Set<UUID>(second.map { $0.uuid })
        
        guard firstUUIDs == secondUUIDs else {
            return false
        }
        
        for uuid in firstUUIDs {
            guard let a = first.first(where: {$0.uuid == uuid}),
                let b = second.first(where: {$0.uuid == uuid}) else {
                return false
            }
            
            return a.compare(to: b)
        }
        
        return true
    }
}

public protocol DeclarableObjectBasics {
    // An id for this SyncedObject. This is required because we're organizing SyncObject's around these UUID's. AKA, declObjectId
    var fileGroupUUID: UUID { get }
    
    // The type of object that this collection of files is representing.
    // E.g., a Neebla image or Neebla URL as above.
    var objectType: String { get }

    // An id for the group of users that have access to this SyncedObject
    var sharingGroupUUID: UUID { get }
}

extension DeclarableObjectBasics {
    func compare<BASICS: DeclarableObjectBasics>(to other: BASICS) -> Bool {
        return self.fileGroupUUID == other.fileGroupUUID &&
            self.objectType == other.objectType &&
            self.sharingGroupUUID == other.sharingGroupUUID
    }
}

/* An abstraction of a data object backed by one or more cloud storage files. Two examples from Neebla:

1) An image: Represented by a (a) jpg image file and (b) a discussion thread file.
2) A website: Represented by (a) an optional jpg file for an image depicting the URL website contents, (b) a file containing the URL for the website, and (c) a discussion thread file.

Representations in terms of a set of files are selected both in terms of the need for storing information for an application's data object, and in terms of having representations that are basically intelligible to a user when stored in their cloud storage. For example, it wouldn't be suitable to compress data files in a non-obvious encoding. JPEG format is fine as it's widely used, and zip compression could be fine as well. But a proprietary compression algorithm not widely used would not be suitable.
*/
public protocol DeclarableObject: DeclarableObjectBasics {
    associatedtype DeclaredFile: DeclarableFile
    var declaredFiles: Set<DeclaredFile> { get }
}

extension DeclarableObject {
    var declObjectId: UUID {
        return fileGroupUUID
    }
    
    func declCompare<OBJ: DeclarableObject>(to other: OBJ) -> Bool {
        return self.compare(to: other) &&
            DeclaredFile.compare(first: self.declaredFiles, second: other.declaredFiles)
    }
}

