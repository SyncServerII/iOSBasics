//
//  UploadObjectTracker.swift
//  
//
//  Created by Christopher G Prince on 9/4/20.
//

import SQLite
import Foundation
import ServerShared

// A record is added each time the SyncServer `queue` method is called.

class UploadObjectTracker: DatabaseModel {
    let db: Connection
    var id: Int64!
     
    static let fileGroupUUIDField = Field("fileGroupUUID", \M.fileGroupUUID)
    var fileGroupUUID: UUID
    
    init(db: Connection,
        id: Int64! = nil,
        fileGroupUUID: UUID) throws {
        
        self.db = db
        self.id = id
        self.fileGroupUUID = fileGroupUUID
    }
    
    // MARK: DatabaseModel
    
    static func createTable(db: Connection) throws {
        try startCreateTable(db: db) { t in
            t.column(idField.description, primaryKey: true)
            t.column(fileGroupUUIDField.description)
        }
    }
    
    static func rowToModel(db: Connection, row: Row) throws -> UploadObjectTracker {
        return try UploadObjectTracker(db: db,
            id: row[Self.idField.description],
            fileGroupUUID: row[Self.fileGroupUUIDField.description]
        )
    }
    
    func insert() throws {
        try doInsertRow(db: db, values:
            Self.fileGroupUUIDField.description <- fileGroupUUID
        )
    }
}
