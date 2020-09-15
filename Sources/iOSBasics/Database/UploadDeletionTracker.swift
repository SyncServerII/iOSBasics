// Represents a file to be or being deleted on the server.

import SQLite
import Foundation
import ServerShared
import iOSShared

class UploadDeletionTracker: DatabaseModel {
    let db: Connection
    var id: Int64!
    
    static let uuidField = Field("uuid", \M.uuid)
    var uuid: UUID
    
    enum DeletionType : String {
        case fileGroupUUID
        case fileUUID
    }
    
    // This indicates the type of uuid used above.
    static let deletionTypeField = Field("deletionType", \M.deletionType)
    var deletionType: DeletionType
    
    enum Status : String {
        case notStarted
        case deleting
        case waitingForDeferredDeletion
        case done
    }
    
    static let statusField = Field("status", \M.status)
    var status: Status
    
    // Set after deletion request successfully sent to server. In some edge cases this might not get set. E.g., the response from the original deletion was not received despite a successful deletion.
    static let deferredUploadIdField = Field("deferredUploadId", \M.deferredUploadId)
    var deferredUploadId: Int64?
    
    init(db: Connection,
        id: Int64! = nil,
        uuid: UUID,
        deletionType: DeletionType,
        deferredUploadId: Int64?,
        status: Status) throws {

        self.db = db
        self.id = id
        self.uuid = uuid
        self.deletionType = deletionType
        self.deferredUploadId = deferredUploadId
        self.status = status
    }
    
    // MARK: DatabaseModel
    
    static func createTable(db: Connection) throws {
        try startCreateTable(db: db) { t in
            t.column(idField.description, primaryKey: true)
            t.column(deferredUploadIdField.description)
            t.column(statusField.description)
            t.column(uuidField.description)
            t.column(deletionTypeField.description)
        }
    }
    
    static func rowToModel(db: Connection, row: Row) throws -> UploadDeletionTracker {
        return try UploadDeletionTracker(db: db,
            id: row[Self.idField.description],
            uuid: row[Self.uuidField.description],
            deletionType: row[Self.deletionTypeField.description],
            deferredUploadId: row[Self.deferredUploadIdField.description],
            status: row[Self.statusField.description]
        )
    }
    
    func insert() throws {
        try doInsertRow(db: db, values:
            Self.uuidField.description <- uuid,
            Self.deletionTypeField.description <- deletionType,
            Self.statusField.description <- status,
            Self.deferredUploadIdField.description <- deferredUploadId
        )
    }
}
