
import Foundation
import SQLite
import ServerShared
import iOSShared

class DirectoryObjectEntry: DatabaseModel, Equatable {
    let db: Connection
    var id: Int64!
    
    static let objectTypeField = Field("objectType", \M.objectType)
    var objectType: String

    static let fileGroupUUIDField = Field("fileGroupUUID", \M.fileGroupUUID)
    var fileGroupUUID: UUID
    
    static let sharingGroupUUIDField = Field("sharingGroupUUID", \M.sharingGroupUUID)
    var sharingGroupUUID: UUID

    static let cloudStorageTypeField = Field("cloudStorageType", \M.cloudStorageType)
    var cloudStorageType: CloudStorageType

    // When a file group is deleted by the local client, the object is deleted along with all files.
    static let deletedLocallyField = Field("deletedLocally", \M.deletedLocally)
    var deletedLocally: Bool
    
    static let deletedOnServerField = Field("deletedOnServer", \M.deletedOnServer)
    var deletedOnServer: Bool
        
    static func == (lhs: DirectoryObjectEntry, rhs: DirectoryObjectEntry) -> Bool {
        return lhs.id == rhs.id &&
            lhs.fileGroupUUID == rhs.fileGroupUUID &&
            lhs.sharingGroupUUID == rhs.sharingGroupUUID &&
            lhs.objectType == rhs.objectType &&
            lhs.cloudStorageType == rhs.cloudStorageType
    }
    
    static func == (lhs: DirectoryObjectEntry, rhs: FileInfo) -> Bool {
        return lhs.fileGroupUUID.uuidString == rhs.fileGroupUUID &&
            lhs.sharingGroupUUID.uuidString == rhs.sharingGroupUUID &&
            lhs.objectType == rhs.objectType &&
            lhs.cloudStorageType.rawValue == rhs.cloudStorageType
    }
    
    init(db: Connection,
        id: Int64! = nil,
        objectType: String,
        fileGroupUUID: UUID,
        sharingGroupUUID: UUID,
        cloudStorageType: CloudStorageType,
        deletedLocally: Bool,
        deletedOnServer: Bool) throws {
        
        self.db = db
        self.id = id
        self.objectType = objectType
        self.fileGroupUUID = fileGroupUUID
        self.sharingGroupUUID = sharingGroupUUID
        self.cloudStorageType = cloudStorageType
        self.deletedLocally = deletedLocally
        self.deletedOnServer = deletedOnServer
    }
    
    // MARK: DatabaseModel
    
    static func createTable(db: Connection) throws {
        try startCreateTable(db: db) { t in
            t.column(idField.description, primaryKey: true)
            t.column(objectTypeField.description)
            t.column(fileGroupUUIDField.description, unique: true)
            t.column(sharingGroupUUIDField.description)
            t.column(cloudStorageTypeField.description)
            t.column(deletedLocallyField.description)
            t.column(deletedOnServerField.description)
        }
    }
    
    static func rowToModel(db: Connection, row: Row) throws -> DirectoryObjectEntry {
        return try DirectoryObjectEntry(db: db,
            id: row[Self.idField.description],
            objectType: row[Self.objectTypeField.description],
            fileGroupUUID: row[Self.fileGroupUUIDField.description],
            sharingGroupUUID: row[Self.sharingGroupUUIDField.description],
            cloudStorageType: row[Self.cloudStorageTypeField.description],
            deletedLocally: row[Self.deletedLocallyField.description],
            deletedOnServer: row[Self.deletedOnServerField.description]
        )
    }
    
    func insert() throws {
        try doInsertRow(db: db, values:
            Self.objectTypeField.description <- objectType,
            Self.fileGroupUUIDField.description <- fileGroupUUID,
            Self.sharingGroupUUIDField.description <- sharingGroupUUID,
            Self.cloudStorageTypeField.description <- cloudStorageType,
            Self.deletedLocallyField.description <- deletedLocally,
            Self.deletedOnServerField.description <- deletedOnServer
        )
    }
}

extension DirectoryObjectEntry {
    struct ObjectInfo {
        let objectEntry: DirectoryObjectEntry
        
        // All current `DirectoryFileEntry`'s for this object. i.e., for this `fileGroupUUID`.
        let allFileEntries:[DirectoryFileEntry]
    }
    
    static func lookup(fileGroupUUID: UUID, db: Connection) throws -> ObjectInfo? {
        guard let objectEntry = try DirectoryObjectEntry.fetchSingleRow(db: db, where: DirectoryObjectEntry.fileGroupUUIDField.description == fileGroupUUID) else {
            return nil
        }
        
        let fileEntries = try DirectoryFileEntry.fetch(db: db, where: DirectoryObjectEntry.fileGroupUUIDField.description == fileGroupUUID)
        
        return ObjectInfo(objectEntry: objectEntry, allFileEntries: fileEntries)
    }
    
    enum ObjectEntryType {
        case newInstance
        case existing(DirectoryObjectEntry)
    }
    
    // When a specific object instance is being uploaded for the first time, we need to create a new `DirectoryObjectEntry` and new `DirectoryFileEntry`'s as needed too.
    static func createNewInstance(upload: UploadableObject, objectType: DeclaredObjectModel, objectEntryType: ObjectEntryType, cloudStorageType: CloudStorageType, db: Connection) throws -> DirectoryObjectEntry {
        
        let objectEntry:DirectoryObjectEntry
        switch objectEntryType {
        case .existing(let existingObjectEntry):
            objectEntry = existingObjectEntry
        case .newInstance:
            objectEntry = try DirectoryObjectEntry(db: db, objectType: upload.objectType, fileGroupUUID: upload.fileGroupUUID, sharingGroupUUID: upload.sharingGroupUUID, cloudStorageType: cloudStorageType, deletedLocally: false, deletedOnServer: false)
            try objectEntry.insert()
        }

        let creationDate = Date()
        
        for file in upload.uploads {
            let fileEntry = try DirectoryFileEntry(db: db, fileUUID: file.uuid, fileLabel: file.fileLabel, fileGroupUUID: upload.fileGroupUUID, fileVersion: nil, serverFileVersion: nil, deletedLocally: false, deletedOnServer: false, creationDate: creationDate, updateCreationDate: true, goneReason: nil)
            try fileEntry.insert()
        }
        
        return objectEntry
    }
    
    // If the DirectoryObjectEntry exists, it must match the `FileInfo`. If it doesn't exist, it's created.
    static func matchSert(fileInfo: FileInfo, objectType: String, db: Connection) throws -> DirectoryObjectEntry {
        guard let fileGroupUUIDString = fileInfo.fileGroupUUID,
              let fileGroupUUID = UUID(uuidString: fileGroupUUIDString) else {
            throw DatabaseError.invalidUUID
        }
        
        guard let sharingGroupUUIDString = fileInfo.sharingGroupUUID,
              let sharingGroupUUID = UUID(uuidString: sharingGroupUUIDString) else {
            throw DatabaseError.invalidUUID
        }
        
        guard let cloudStorageTypeString = fileInfo.cloudStorageType,
            let cloudStorageType = CloudStorageType(rawValue: cloudStorageTypeString) else {
            throw DatabaseError.badCloudStorageType
        }
        
        if let entry = try DirectoryObjectEntry.fetchSingleRow(db: db, where: DirectoryObjectEntry.fileGroupUUIDField.description == fileGroupUUID) {
            guard entry == fileInfo else {
                throw DatabaseError.notMatching
            }
            
            if entry.deletedOnServer != fileInfo.deleted {
                try entry.update(setters: DirectoryObjectEntry.deletedOnServerField.description <- fileInfo.deleted)
            }
            
            return entry
        }
        else {
            let newEntry = try DirectoryObjectEntry(db: db, objectType: objectType, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, cloudStorageType: cloudStorageType, deletedLocally: fileInfo.deleted, deletedOnServer: fileInfo.deleted)
            try newEntry.insert()
            return newEntry
        }
    }
}
