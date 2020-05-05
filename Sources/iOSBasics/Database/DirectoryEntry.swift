import SQLite
import Foundation
import ServerShared

class DirectoryEntry: DatabaseModel {
    enum DirectoryEntryError: Error {
        case badGoneReason(String)
        case badCloudStorageType(String)
    }
    
    let db: Connection
    var id: Int64!
        
    static let fileUUIDField = Field("fileUUID", \M.fileUUID)
    var fileUUID: String
    
    static let mimeTypeField = Field("mimeType", \M.mimeType)
    var mimeType: String
    
    static let fileVersionField = Field("fileVersion", \M.fileVersion)
    var fileVersion: Int64
    
    static let sharingGroupUUIDField = Field("sharingGroupUUID", \M.sharingGroupUUID)
    var sharingGroupUUID: String

    static let fileGroupUUIDField = Field("fileGroupUUID", \M.fileGroupUUID)
    var fileGroupUUID: String?
    
    static let appMetaDataField = Field("appMetaData", \M.appMetaData)
    var appMetaData: String?

    static let appMetaDataVersionField = Field("appMetaDataVersion", \M.appMetaDataVersion)
    var appMetaDataVersion: Int64?

    static let cloudStorageTypeField = Field("cloudStorageType", \M.cloudStorageType)
    var cloudStorageType: String

    static let deletedLocallyField = Field("deletedLocally", \M.deletedLocally)
    var deletedLocally: Bool
    
    static let deletedOnServerField = Field("deletedOnServer", \M.deletedOnServer)
    var deletedOnServer: Bool
    
    static let goneReasonField = Field("goneReason", \M.goneReason)
    var goneReason: String?
    
    init(db: Connection,
        fileUUID: String,
        mimeType: String,
        fileVersion: Int64,
        sharingGroupUUID: String,
        cloudStorageType: String,
        deletedLocally: Bool,
        deletedOnServer: Bool,
        appMetaData: String? = nil,
        appMetaDataVersion: Int64? = nil,
        fileGroupUUID: String? = nil,
        goneReason: String? = nil) throws {
        
        guard let goneReasonString = goneReason,
            let _ = GoneReason(rawValue: goneReasonString) else {
            throw DirectoryEntryError.badGoneReason(goneReason!)
        }
        
        guard let _ = CloudStorageType(rawValue: cloudStorageType) else {
            throw DirectoryEntryError.badCloudStorageType(cloudStorageType)
        }
                
        self.db = db
        self.fileUUID = fileUUID
        self.mimeType = mimeType
        self.fileVersion = fileVersion
        self.sharingGroupUUID = sharingGroupUUID
        self.cloudStorageType = cloudStorageType
        self.appMetaData = appMetaData
        self.appMetaDataVersion = appMetaDataVersion
        self.fileGroupUUID = fileGroupUUID
        self.deletedLocally = deletedLocally
        self.deletedOnServer = deletedOnServer
        self.goneReason = goneReason
    }
    
    // MARK: DatabaseModel
    
    static func createTable(db: Connection) throws {
        try startCreateTable(db: db) { t in
            t.column(fileUUIDField.description, primaryKey: true)
            t.column(mimeTypeField.description)
            t.column(fileVersionField.description)
            t.column(sharingGroupUUIDField.description)
            t.column(cloudStorageTypeField.description)
            t.column(appMetaDataField.description)
            t.column(appMetaDataVersionField.description)
            t.column(fileGroupUUIDField.description)
            t.column(deletedLocallyField.description)
            t.column(deletedOnServerField.description)
            t.column(goneReasonField.description)
        }
    }
    
    static func rowToModel(db: Connection, row: Row) throws -> DirectoryEntry {
        return try DirectoryEntry(db: db,
            fileUUID: row[Self.fileUUIDField.description],
            mimeType: row[Self.mimeTypeField.description],
            fileVersion: row[Self.fileVersionField.description],
            sharingGroupUUID: row[Self.sharingGroupUUIDField.description],
            cloudStorageType: row[Self.cloudStorageTypeField.description],
            deletedLocally: row[Self.deletedLocallyField.description],
            deletedOnServer: row[Self.deletedOnServerField.description],
            appMetaData: row[Self.appMetaDataField.description],
            appMetaDataVersion: row[Self.appMetaDataVersionField.description],
            fileGroupUUID: row[Self.fileGroupUUIDField.description],
            goneReason: row[Self.goneReasonField.description]
        )
    }
    
    func insert() throws {        
        try doInsertRow(db: db, values:
            Self.fileUUIDField.description <- fileUUID,
            Self.mimeTypeField.description <- mimeType,
            Self.fileVersionField.description <- fileVersion,
            Self.sharingGroupUUIDField.description <- sharingGroupUUID,
            Self.cloudStorageTypeField.description <- cloudStorageType,
            Self.appMetaDataField.description <- appMetaData,
            Self.appMetaDataVersionField.description <- appMetaDataVersion,
            Self.fileGroupUUIDField.description <- fileGroupUUID,
            Self.deletedLocallyField.description <- deletedLocally,
            Self.deletedOnServerField.description <- deletedOnServer,
            Self.goneReasonField.description <- goneReason
        )
    }
}






