import SQLite
import Foundation
import ServerShared

// Represents a file the iOSBasics client knows about in regards to the current signed in user. Used to represent a directory of all files for the current signed in user. Each file is part of a specific DeclaredObject.

class DirectoryEntry: DatabaseModel {
    enum DirectoryEntryError: Error {
        case badGoneReason(String)
        case badCloudStorageType(String)
    }
    
    let db: Connection
    var id: Int64!
        
    static let fileUUIDField = Field("fileUUID", \M.fileUUID)
    var fileUUID: UUID
    
    // This will be 0 after a first *successful* upload for a file initiated by the local client. After that, it will only be updated when a specific file version is downloaded in its entirety from the server. It cannot be updated for vN files on deferred upload completion because the local client, if other competing clients are concurrently making changes, may not have the complete file update for a specific version.
    static let fileVersionField = Field("fileVersion", \M.fileVersion)
    var fileVersion: Int32?

    static let deletedLocallyField = Field("deletedLocally", \M.deletedLocally)
    var deletedLocally: Bool
    
    static let deletedOnServerField = Field("deletedOnServer", \M.deletedOnServer)
    var deletedOnServer: Bool
    
    static let goneReasonField = Field("goneReason", \M.goneReason)
    var goneReason: String?
    
    init(db: Connection,
        id: Int64! = nil,
        fileUUID: UUID,
        fileVersion: FileVersionInt?,
        deletedLocally: Bool,
        deletedOnServer: Bool,
        goneReason: String? = nil) throws {
        
        if let goneReason = goneReason {
            guard let _ = GoneReason(rawValue: goneReason) else {
                throw DirectoryEntryError.badGoneReason(goneReason)
            }
        }
        
        self.db = db
        self.id = id
        self.fileUUID = fileUUID
        self.fileVersion = fileVersion
        self.deletedLocally = deletedLocally
        self.deletedOnServer = deletedOnServer
        self.goneReason = goneReason
    }
    
    // MARK: DatabaseModel
    
    static func createTable(db: Connection) throws {
        try startCreateTable(db: db) { t in
            t.column(idField.description, primaryKey: true)
            t.column(fileUUIDField.description)
            t.column(fileVersionField.description)
            t.column(deletedLocallyField.description)
            t.column(deletedOnServerField.description)
            t.column(goneReasonField.description)
        }
    }
    
    static func rowToModel(db: Connection, row: Row) throws -> DirectoryEntry {
        return try DirectoryEntry(db: db,
            id: row[Self.idField.description],
            fileUUID: row[Self.fileUUIDField.description],
            fileVersion: row[Self.fileVersionField.description],
            deletedLocally: row[Self.deletedLocallyField.description],
            deletedOnServer: row[Self.deletedOnServerField.description],
            goneReason: row[Self.goneReasonField.description]
        )
    }
    
    func insert() throws {        
        try doInsertRow(db: db, values:
            Self.fileUUIDField.description <- fileUUID,
            Self.fileVersionField.description <- fileVersion,
            Self.deletedLocallyField.description <- deletedLocally,
            Self.deletedOnServerField.description <- deletedOnServer,
            Self.goneReasonField.description <- goneReason
        )
    }
}

extension DirectoryEntry {
    static func fileVersion(fileUUID: UUID, db: Connection) throws -> FileVersionInt? {
        guard let entry = try DirectoryEntry.fetchSingleRow(db: db, where:
            fileUUID == DirectoryEntry.fileUUIDField.description) else {
            throw DatabaseModelError.noObject
        }
        
        return entry.fileVersion
    }
    
    enum UploadState {
        case v0
        case vN
    }

    // Are all files we're uploading either v0 or vN? Return nil if all files are not either v0 or vN.
    static func versionOfAllFiles(fileUUIDs:[UUID], db: Connection) throws -> UploadState? {
        var uploadState = Set<UploadState>()
        
        for fileUUID in fileUUIDs {
            let version = try DirectoryEntry.fileVersion(fileUUID: fileUUID, db: db)
            uploadState.insert(version == nil ? .v0 : .vN)
        }
        
        guard uploadState.count == 1, let uploadVersion = uploadState.first else {
            return nil
        }
        
        return uploadVersion
    }
}
