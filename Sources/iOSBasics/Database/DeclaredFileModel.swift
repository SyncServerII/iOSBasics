//
//  DeclaredFileModel.swift
//  
//
//  Created by Christopher G Prince on 9/3/20.
//

import Foundation
import SQLite
import ServerShared

// Declared files for DeclaredObject's.

class DeclaredFileModel: DatabaseModel, Equatable, Hashable, DeclarableFile {
    let db: Connection
    var id: Int64!
    
    // Key into DeclaredObject
    static let fileGroupUUIDField = Field("fileGroupUUID", \M.fileGroupUUID)
    var fileGroupUUID: UUID
    
    static let uuidField = Field("uuid", \M.uuid)
    var uuid: UUID
    
    static let mimeTypeField = Field("mimeType", \M.mimeType)
    var mimeType: MimeType
    
    static let cloudStorageTypeField = Field("cloudStorageType", \M.cloudStorageType)
    var cloudStorageType: CloudStorageType

    static let appMetaDataField = Field("appMetaData", \M.appMetaData)
    var appMetaData: String?

    static let changeResolverNameField = Field("changeResolverName", \M.changeResolverName)
    var changeResolverName: String?
    
    init(db: Connection,
        id: Int64! = nil,
        fileGroupUUID: UUID,
        uuid: UUID,
        mimeType: MimeType,
        cloudStorageType: CloudStorageType,
        appMetaData: String?,
        changeResolverName: String?) throws {
        self.db = db
        self.id = id
        self.fileGroupUUID = fileGroupUUID
        self.uuid = uuid
        self.mimeType = mimeType
        self.cloudStorageType = cloudStorageType
        self.appMetaData = appMetaData
        self.changeResolverName = changeResolverName
    }
    
    // Returns true iff the static or invariants parts of `self` and the fileInfo are the same.
    func sameInvariants(fileInfo: FileInfo) -> Bool {
        guard fileGroupUUID.uuidString == fileInfo.fileGroupUUID else {
            return false
        }
        
        guard uuid.uuidString == fileInfo.fileUUID else {
            return false
        }

        guard mimeType.rawValue == fileInfo.mimeType else {
            return false
        }

        guard cloudStorageType.rawValue == fileInfo.cloudStorageType else {
            return false
        }

        #warning("Should have comparisons for appMetaData and for changeResolverName")
        
        return true
    }
    
    static func == (lhs: DeclaredFileModel, rhs: DeclaredFileModel) -> Bool {
        return lhs.id == rhs.id &&
            lhs.fileGroupUUID == rhs.fileGroupUUID &&
            lhs.uuid == rhs.uuid &&
            lhs.mimeType == rhs.mimeType &&
            lhs.cloudStorageType == rhs.cloudStorageType &&
            lhs.appMetaData == rhs.appMetaData &&
            lhs.changeResolverName == rhs.changeResolverName
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(fileGroupUUID)
    }
    
    static func createTable(db: Connection) throws {
        try startCreateTable(db: db) { t in
            t.column(idField.description, primaryKey: true)
            t.column(fileGroupUUIDField.description)
            t.column(uuidField.description, unique: true)
            t.column(mimeTypeField.description)
            t.column(cloudStorageTypeField.description)
            t.column(appMetaDataField.description)
            t.column(changeResolverNameField.description)
        }
    }
    
    static func rowToModel(db: Connection, row: Row) throws -> DeclaredFileModel {
        return try DeclaredFileModel(db: db,
            id: row[Self.idField.description],
            fileGroupUUID: row[Self.fileGroupUUIDField.description],
            uuid: row[Self.uuidField.description],
            mimeType: row[Self.mimeTypeField.description],
            cloudStorageType: row[Self.cloudStorageTypeField.description],
            appMetaData: row[Self.appMetaDataField.description],
            changeResolverName: row[Self.changeResolverNameField.description]
        )
    }

    func insert() throws {
        try doInsertRow(db: db, values:
            Self.fileGroupUUIDField.description <- fileGroupUUID,
            Self.uuidField.description <- uuid,
            Self.cloudStorageTypeField.description <- cloudStorageType,
            Self.mimeTypeField.description <- mimeType,
            Self.appMetaDataField.description <- appMetaData,
            Self.changeResolverNameField.description <- changeResolverName
        )
    }
}

extension DeclaredFileModel {
    // Throws error if `declaredFiles` differ from corresponding `DeclaredFileModel`'s in the database.
    static func lookupModels<FILE: DeclarableFile>(for declaredFiles: Set<FILE>, inFileGroupUUID fileGroupUUID: UUID, db: Connection) throws -> [DeclaredFileModel] {

        let declaredFilesInDatabase = try DeclaredFileModel.fetch(db: db, where: fileGroupUUID == DeclaredFileModel.fileGroupUUIDField.description)
        
        let first = Set<DeclaredFileModel>(declaredFilesInDatabase)

        guard DeclaredFileModel.compare(first: first, second: declaredFiles) else {
            throw DatabaseModelError.declarationDifferentThanModel
        }
        
        return declaredFilesInDatabase
    }
    
    @discardableResult
    static func upsert(fileInfo: FileInfo, object: DeclaredObjectModel, db: Connection) throws -> DeclaredFileModel {
        guard let fileUUIDString = fileInfo.fileUUID,
            let fileUUID = UUID(uuidString: fileUUIDString),
            let fileGroupUUIDString = fileInfo.fileGroupUUID,
            let fileGroupUUID = UUID(uuidString: fileGroupUUIDString) else {
            throw DatabaseModelError.invalidUUID
        }
        
        guard let mimeTypeString = fileInfo.mimeType,
            let mimeType = MimeType(rawValue: mimeTypeString) else {
            throw DatabaseModelError.badMimeType
        }
        
        guard let cloudStorageTypeString = fileInfo.cloudStorageType,
            let cloudStorageType = CloudStorageType(rawValue: cloudStorageTypeString) else {
            throw DatabaseModelError.badCloudStorageType
        }

        if let entry = try DeclaredFileModel.fetchSingleRow(db: db, where: DeclaredFileModel.uuidField.description == fileUUID) {
            // These don't change.
            return entry
        }
        else {
            #warning("TODO: Need to add in appMetaData and changeResolverName once those are in FileInfo.")
            let entry = try DeclaredFileModel(db: db, fileGroupUUID: fileGroupUUID, uuid: fileUUID, mimeType: mimeType, cloudStorageType: cloudStorageType, appMetaData: nil, changeResolverName: nil)
            try entry.insert()
            return entry
        }
    }
}
