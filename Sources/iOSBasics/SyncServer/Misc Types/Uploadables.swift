
import Foundation

public enum LocalPersistence {
    case copy
    case immutable
    
    var isCopy: Bool {
        return self == .copy
    }
}

public enum UploadDataSource: Equatable {
    case data(Data)
    
    // SyncServer interface will make a copy of this file. The underlying file might change while the SyncServer method is doing its work.
    case copy(URL)
    
    // SyncServer interface does *not* make a copy of this file. The underlying file is assumed to *not* change while the SyncServer method is doing its work.
    case immutable(URL)
    
    var isCopy: Bool {
        switch self {
        case .copy, .data:
            return true
        case .immutable:
            return false
        }
    }
}

public protocol UploadableFile: File {
    // Reference for DeclarableFile
    var fileLabel: String {get}
    
    var appMetaData: String? {get}
    
    var dataSource: UploadDataSource {get}
}

extension UploadableFile {
    public func compare<FILE: UploadableFile>(to other: FILE) -> Bool {
        return self.uuid == other.uuid &&
            self.dataSource == other.dataSource
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

public protocol UploadableObject {
    // References a specific DeclarableObject
    var objectType: String {get}
    
    // On a first upload, this establishes a specific object with this file group and this sharing group. The file group must be new, on the first upload, for this object. The user must already be a member of this sharing group on the server.
    var fileGroupUUID: UUID {get}
    var sharingGroupUUID: UUID {get}
    
    // On a first upload, each element in this set binds particular UUID's to `fileLabel`'s for the DeclarableObject and must be used with this binding thereafter.
    var uploads: [UploadableFile] {get}
}
