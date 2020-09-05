//
//  UploadObjectTracker.swift
//  
//
//  Created by Christopher G Prince on 9/4/20.
//

import SQLite
import Foundation
import ServerShared

class UploadObjectTracker: DatabaseModel {
    let db: Connection
    var id: Int64!
     
    static let fileGroupUUIDField = Field("fileGroupUUID", \M.fileGroupUUID)
    var fileGroupUUID: UUID
    
    static let objectTypeField = Field("objectType", \M.objectType)
    var objectType: String

    static let sharingGroupUUIDField = Field("sharingGroupUUID", \M.sharingGroupUUID)
    var sharingGroupUUID: UUID
    
    init(db: Connection,
        id: Int64! = nil,
        fileGroupUUID: UUID,
        objectType: String,
        sharingGroupUUID:UUID) throws {
        
        self.db = db
        self.id = id
        self.fileGroupUUID = fileGroupUUID
        self.objectType = objectType
        self.sharingGroupUUID = sharingGroupUUID
    }
    
    // MARK: DatabaseModel
    
    static func createTable(db: Connection) throws {
        try startCreateTable(db: db) { t in
            t.column(idField.description, primaryKey: true)
            t.column(fileGroupUUIDField.description)
            t.column(objectTypeField.description)
            t.column(sharingGroupUUIDField.description)
        }
    }
    
    static func rowToModel(db: Connection, row: Row) throws -> UploadObjectTracker {
        return try UploadObjectTracker(db: db,
            id: row[Self.idField.description],
            fileGroupUUID: row[Self.fileGroupUUIDField.description],
            objectType: row[Self.objectTypeField.description],
            sharingGroupUUID: row[Self.sharingGroupUUIDField.description]
        )
    }
    
    func insert() throws {
        try doInsertRow(db: db, values:
            Self.fileGroupUUIDField.description <- fileGroupUUID,
            Self.objectTypeField.description <- objectType,
            Self.sharingGroupUUIDField.description <- sharingGroupUUID
        )
    }
}
