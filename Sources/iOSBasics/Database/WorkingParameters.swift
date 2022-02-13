// This table has just a single row.

import SQLite
import Foundation
import ServerShared
import iOSShared

class WorkingParameters: DatabaseModel {
    let db: Connection
    var id: Int64!

    // The sharing group we're currently fetching an index for.
    static let currentSharingGroupField = Field("currentSharingGroup", \M.currentSharingGroup)
    var currentSharingGroup: UUID?
    
    // All parameters are optional for `setup` method.
    init(db: Connection,
        id: Int64! = nil,
        currentSharingGroup: UUID? = nil) throws {
        
        self.db = db
        self.id = id
        self.currentSharingGroup = currentSharingGroup
    }
    
    // MARK: DatabaseModel
    
    static func createTable(db: Connection) throws {
        try startCreateTable(db: db) { t in
            t.column(idField.description, primaryKey: true)
            t.column(currentSharingGroupField.description)
        }
    }
    
    static func rowToModel(db: Connection, row: Row) throws -> WorkingParameters {
        return try WorkingParameters(db: db,
            id: row[Self.idField.description],
            currentSharingGroup: row[Self.currentSharingGroupField.description]
        )
    }
    
    func insert() throws {
        try doInsertRow(db: db, values:
            Self.currentSharingGroupField.description <- currentSharingGroup
        )
    }
}

extension WorkingParameters {
    static func setup(db: Connection) throws {
        let rows = try WorkingParameters.fetch(db: db)
        if rows.count == 0 {
            let entry = try WorkingParameters(db: db)
            try entry.insert()
        }
    }
    
    static func singleton(db: Connection) throws -> WorkingParameters {
        let rows = try WorkingParameters.fetch(db: db)
        guard rows.count == 1 else {
            throw DatabaseError.notExactlyOneRow(message: "WorkingParameters:  singleton")
        }
        
        return rows[0]
    }
}
