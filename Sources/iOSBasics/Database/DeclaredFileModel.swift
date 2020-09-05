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
            t.column(uuidField.description)
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

