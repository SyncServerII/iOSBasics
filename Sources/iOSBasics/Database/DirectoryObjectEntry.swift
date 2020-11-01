
import Foundation
import SQLite

class DirectoryObjectEntry: DatabaseModel, Equatable {
    let db: Connection
    var id: Int64!
    
    static let objectTypeField = Field("objectType", \M.objectType)
    var objectType: String

    static let fileGroupUUIDField = Field("fileGroupUUID", \M.fileGroupUUID)
    var fileGroupUUID: UUID
    
    static let sharingGroupUUIDField = Field("sharingGroupUUID", \M.sharingGroupUUID)
    var sharingGroupUUID: UUID
    
    static func == (lhs: DirectoryObjectEntry, rhs: DirectoryObjectEntry) -> Bool {
        return lhs.id == rhs.id &&
            lhs.fileGroupUUID == rhs.fileGroupUUID &&
            lhs.sharingGroupUUID == rhs.sharingGroupUUID &&
            lhs.objectType == rhs.objectType
    }
    
    init(db: Connection,
        id: Int64! = nil,
        objectType: String,
        fileGroupUUID: UUID,
        sharingGroupUUID: UUID) throws {
        
        self.db = db
        self.id = id
        self.objectType = objectType
        self.fileGroupUUID = fileGroupUUID
        self.sharingGroupUUID = sharingGroupUUID
    }
    
    // MARK: DatabaseModel
    
    static func createTable(db: Connection) throws {
        try startCreateTable(db: db) { t in
            t.column(idField.description, primaryKey: true)
            t.column(objectTypeField.description)
            t.column(fileGroupUUIDField.description)
            t.column(sharingGroupUUIDField.description)
        }
    }
    
    static func rowToModel(db: Connection, row: Row) throws -> DirectoryObjectEntry {
        return try DirectoryObjectEntry(db: db,
            id: row[Self.idField.description],
            objectType: row[Self.objectTypeField.description],
            fileGroupUUID: row[Self.fileGroupUUIDField.description],
            sharingGroupUUID: row[Self.sharingGroupUUIDField.description]
        )
    }
    
    func insert() throws {
        try doInsertRow(db: db, values:
            Self.objectTypeField.description <- objectType,
            Self.fileGroupUUIDField.description <- fileGroupUUID,
            Self.sharingGroupUUIDField.description <- sharingGroupUUID
        )
    }
}

extension DirectoryObjectEntry {
    struct ObjectInfo {
        let objectEntry: DirectoryObjectEntry
        
        // All current `DirectoryFileEntry`'s for this object. i.e., for this `fileGroupUUID`.
        let allEntries:[DirectoryFileEntry]
    }
    
    static func lookup(fileGroupUUID: UUID, db: Connection) throws -> ObjectInfo? {
        guard let objectEntry = try DirectoryObjectEntry.fetchSingleRow(db: db, where: DirectoryObjectEntry.fileGroupUUIDField.description == fileGroupUUID) else {
            return nil
        }
        
        let fileEntries = try DirectoryFileEntry.fetch(db: db, where: DirectoryObjectEntry.fileGroupUUIDField.description == fileGroupUUID)
        
        return ObjectInfo(objectEntry: objectEntry, allEntries: fileEntries)
    }
    
    // When a specific object instance is being uploaded for the first time, we need to create a new `DirectoryObjectEntry` and new `DirectoryFileEntry`'s as needed too.
    // Throws an error if `upload.sharingGroupUUID` doesn't exist as a SharingEntry.
    static func createNewInstance(upload: UploadableObject, objectType: DeclaredObjectModel, db: Connection) throws -> DirectoryObjectEntry {
    
        guard let _ = try SharingEntry.fetchSingleRow(db: db, where: SharingEntry.sharingGroupUUIDField.description == upload.sharingGroupUUID) else {
            throw DatabaseModelError.invalidSharingGroupUUID
        }
        
        let objectEntry = try DirectoryObjectEntry(db: db, objectType: upload.objectType, fileGroupUUID: upload.fileGroupUUID, sharingGroupUUID: upload.sharingGroupUUID)
        try objectEntry.insert()
        
        for file in upload.uploads {
            let fileEntry = try DirectoryFileEntry(db: db, fileUUID: file.uuid, fileLabel: file.fileLabel, fileGroupUUID: upload.fileGroupUUID, fileVersion: nil, serverFileVersion: nil, deletedLocally: false, deletedOnServer: false, goneReason: nil)
            try fileEntry.insert()
        }
        
        return objectEntry
    }
}
