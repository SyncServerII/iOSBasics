import SQLite
import Foundation
import ServerShared

// Represents a file the iOSBasics client knows about in regards to the current signed in user. Used to represent a directory of all files for the current signed in user. Each file is part of a specific DeclaredObject.

class DirectoryEntry: DatabaseModel, Equatable {
    enum DirectoryEntryError: Error {
        case badGoneReason(String)
        case badCloudStorageType(String)
    }
    
    let db: Connection
    var id: Int64!
        
    static let fileUUIDField = Field("fileUUID", \M.fileUUID)
    var fileUUID: UUID

    static let fileGroupUUIDField = Field("fileGroupUUID", \M.fileGroupUUID)
    var fileGroupUUID: UUID
    
    static let sharingGroupUUIDField = Field("sharingGroupUUID", \M.sharingGroupUUID)
    var sharingGroupUUID: UUID
    
    // The version of the file locally.
    // This will be 0 after a first *successful* upload for a file initiated by the local client. After that, it will only be updated when a specific file version is downloaded in its entirety from the server. It cannot be updated for vN files on deferred upload completion because the local client, if other competing clients are concurrently making changes, may not have the complete file update for a specific version.
    // This can be nil, and the `serverFileVersion` can be non-nil. This will indicate a file that has not been created locally, that needs downloading.
    static let fileVersionField = Field("fileVersion", \M.fileVersion)
    var fileVersion: Int32?
    
    // The version of the file on the server.
    static let serverFileVersionField = Field("serverFileVersion", \M.serverFileVersion)
    var serverFileVersion: Int32?
    
    enum FileState {
        case needsUpload
        case needsDownload
        case noChange
    }
    
    var fileState: FileState {
        switch (fileVersion, serverFileVersion) {
        case (.none, .none):
            // File has just been created.
            return .needsUpload
            
        case (.none, .some):
            // File was obtained via an `index` request to server. Needs download.
            return .needsDownload
            
        case (.some, .none):
            // File created locally, but no change on server or no `index` request to update serverFileVersion.
            return .noChange
            
        case (.some(let fileVersion), .some(let serverFileVersion)):
            if fileVersion < serverFileVersion {
                return .needsDownload
            }
            else {
                return .noChange
            }
        }
    }

    // When a file group is deleted by the local client, all files in that group are marked as deleted locally.
    static let deletedLocallyField = Field("deletedLocally", \M.deletedLocally)
    var deletedLocally: Bool
    
    static let deletedOnServerField = Field("deletedOnServer", \M.deletedOnServer)
    var deletedOnServer: Bool
    
    static let goneReasonField = Field("goneReason", \M.goneReason)
    var goneReason: String?
    
    static func == (lhs: DirectoryEntry, rhs: DirectoryEntry) -> Bool {
        return lhs.id == rhs.id &&
            lhs.fileUUID == rhs.fileUUID &&
            lhs.fileVersion == rhs.fileVersion &&
            lhs.fileGroupUUID == rhs.fileGroupUUID &&
            lhs.sharingGroupUUID == rhs.sharingGroupUUID &&
            lhs.serverFileVersion == rhs.serverFileVersion &&
            lhs.deletedLocally == rhs.deletedLocally &&
            lhs.deletedOnServer == rhs.deletedOnServer &&
            lhs.goneReason == rhs.goneReason
    }
    
    // Returns true iff the static or invariants parts of `self` and the fileInfo are the same.
    func sameInvariants(fileInfo: FileInfo) -> Bool {
        guard fileUUID.uuidString == fileInfo.fileUUID else {
            return false
        }
        
        guard fileGroupUUID.uuidString == fileInfo.fileGroupUUID else {
            return false
        }
        
        guard sharingGroupUUID.uuidString == fileInfo.sharingGroupUUID else {
            return false
        }
        
        return true
    }
    
    init(db: Connection,
        id: Int64! = nil,
        fileUUID: UUID,
        fileGroupUUID: UUID,
        sharingGroupUUID: UUID,
        fileVersion: FileVersionInt?,
        serverFileVersion: FileVersionInt?,
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
        self.fileGroupUUID = fileGroupUUID
        self.sharingGroupUUID = sharingGroupUUID
        self.fileVersion = fileVersion
        self.serverFileVersion = serverFileVersion
        self.deletedLocally = deletedLocally
        self.deletedOnServer = deletedOnServer
        self.goneReason = goneReason
    }
    
    // MARK: DatabaseModel
    
    static func createTable(db: Connection) throws {
        try startCreateTable(db: db) { t in
            t.column(idField.description, primaryKey: true)
            t.column(fileUUIDField.description, unique: true)
            t.column(fileGroupUUIDField.description)
            t.column(sharingGroupUUIDField.description)
            t.column(fileVersionField.description)
            t.column(serverFileVersionField.description)
            t.column(deletedLocallyField.description)
            t.column(deletedOnServerField.description)
            t.column(goneReasonField.description)
        }
    }
    
    static func rowToModel(db: Connection, row: Row) throws -> DirectoryEntry {
        return try DirectoryEntry(db: db,
            id: row[Self.idField.description],
            fileUUID: row[Self.fileUUIDField.description],
            fileGroupUUID: row[Self.fileGroupUUIDField.description],
            sharingGroupUUID: row[Self.sharingGroupUUIDField.description],
            fileVersion: row[Self.fileVersionField.description],
            serverFileVersion: row[Self.serverFileVersionField.description],
            deletedLocally: row[Self.deletedLocallyField.description],
            deletedOnServer: row[Self.deletedOnServerField.description],
            goneReason: row[Self.goneReasonField.description]
        )
    }
    
    func insert() throws {        
        try doInsertRow(db: db, values:
            Self.fileUUIDField.description <- fileUUID,
            Self.fileGroupUUIDField.description <- fileGroupUUID,
            Self.sharingGroupUUIDField.description <- sharingGroupUUID,
            Self.fileVersionField.description <- fileVersion,
            Self.serverFileVersionField.description <- serverFileVersion,
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
    
    // Create a `DirectoryEntry` per file in `declaredFiles`.
    static func createEntries<FILE: DeclarableFile>(for declaredFiles: Set<FILE>, fileGroupUUID: UUID, sharingGroupUUID: UUID, db: Connection) throws {
        for file in declaredFiles {
            // `fileVersion` is specifically nil-- until we get a first successful upload of v0.
            let dirEntry = try DirectoryEntry(db: db, fileUUID: file.uuid, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, fileVersion: nil, serverFileVersion: nil, deletedLocally: false, deletedOnServer: false, goneReason: nil)
            try dirEntry.insert()
        }
    }
    
    // See if there is exactly one DirectoryEntry per `DeclaredFileModel`
    static func isOneEntryForEach(declaredModels: [DeclaredFileModel], db: Connection) throws -> Bool {
        for file in declaredModels {
            let rows = try DirectoryEntry.fetch(db: db, where: file.uuid == DirectoryEntry.fileUUIDField.description)
            guard rows.count == 1 else {
                return false
            }
        }
        
        return true
    }
    
    static func anyFileIsDeleted(fileUUIDs: [UUID], db: Connection) throws -> Bool {
        for fileUUID in fileUUIDs {
            guard let entry = try DirectoryEntry.fetchSingleRow(db: db, where: fileUUID == DirectoryEntry.fileUUIDField.description) else {
                throw DatabaseModelError.noObject
            }
            
            if entry.deletedLocally || entry.deletedOnServer {
                return true
            }
        }
        
        return false
    }
    
    // The `fileInfo` is assumed to come from the server.
    @discardableResult
    static func upsert(fileInfo: FileInfo, db: Connection) throws ->
        (DirectoryEntry, markedForDeletion: Bool) {
        
        let resultEntry:DirectoryEntry
        var markedForDeletion = false
        
        guard let fileUUIDString = fileInfo.fileUUID,
            let fileUUID = UUID(uuidString: fileUUIDString) else {
            throw DatabaseModelError.invalidUUID
        }

        if let entry = try DirectoryEntry.fetchSingleRow(db: db, where: DirectoryEntry.fileUUIDField.description == fileUUID) {
            try entry.update(setters: DirectoryEntry.serverFileVersionField.description <- fileInfo.fileVersion)
            if fileInfo.deleted && !entry.deletedOnServer {
                // Specifically *not* changing `deletedLocallyField` because the difference between these two (i.e., deletedLocally false, and deletedOnServer true) will be used to drive local deletion for the client.
                try entry.update(setters:
                    DirectoryEntry.deletedOnServerField.description <- true
                )
                markedForDeletion = true
            }
            resultEntry = entry
        }
        else {
            // Creation of a DirectoryEntry for a file not yet known to the local client.
            guard let sharingGroupUUIDString = fileInfo.sharingGroupUUID,
                let sharingGroupUUID = UUID(uuidString: sharingGroupUUIDString) else {
                throw DatabaseModelError.invalidUUID
            }
            
            guard let fileGroupUUIDString = fileInfo.fileGroupUUID,
                let fileGroupUUID = UUID(uuidString: fileGroupUUIDString) else {
                throw DatabaseModelError.invalidUUID
            }
            
            // `deletedLocally` is set to the same state as `deletedOnServer` because this is a file not yet known the local client. This just indicates that, if deleted on server already, the local client doesn't have to take any deletion actions for this file. If not deleted on the server, then the file isn't deleted locally either.
            let entry = try DirectoryEntry(db: db, fileUUID: fileUUID, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, fileVersion:  nil, serverFileVersion: fileInfo.fileVersion, deletedLocally: fileInfo.deleted, deletedOnServer: fileInfo.deleted, goneReason: nil)
            try entry.insert()
            resultEntry = entry
        }
        
        return (resultEntry, markedForDeletion)
    }
    
    // It is an error for one of the uploadables to not be in the DirectoryEntry's
    static func lookupFor<UPL: UploadableFile>(uploadables: Set<UPL>, db: Connection) throws -> [DirectoryEntry] {
        var result = [DirectoryEntry]()
        
        for uploadable in uploadables {
            guard let entry = try DirectoryEntry.fetchSingleRow(db: db, where: DirectoryEntry.fileUUIDField.description == uploadable.uuid) else {
                throw DatabaseModelError.notExactlyOneRow
            }
            
            result += [entry]
        }
        
        return result
    }
}
