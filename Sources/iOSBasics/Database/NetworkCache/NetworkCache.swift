import SQLite
import Foundation
import ServerShared

class NetworkCache: DatabaseModel {
    let db: Connection
    var id: Int64!
    
    // URLSessionTask taskIdentifier
    static let taskIdentifierField = Field("taskIdentifier", \M.taskIdentifier)
    var taskIdentifier: Int
    
    static let uuidField = Field("uuid", \M.uuid)
    var uuid: UUID
    
    static let fileVersionField = Field("fileVersion", \M.fileVersion)
    var fileVersion: FileVersionInt?
    
    // A local database tracker id, e.g., an UploadObjectTracker id.
    static let trackerIdField = Field("trackerId", \M.trackerId)
    var trackerId: Int64
    
    // Request dependent info.
    static let requestInfoField = Field("requestInfo", \M.requestInfo)
    var requestInfo: Data?
    
    static let transferField = Field("transfer", \M.transfer)
    var transfer: NetworkTransfer?

    init(db: Connection,
        id: Int64! = nil,
        taskIdentifier: Int,
        uuid: UUID,
        trackerId: Int64,
        fileVersion: FileVersionInt?,
        transfer: NetworkTransfer?,
        requestInfo: Data? = nil) throws {
                
        self.db = db
        self.id = id
        self.taskIdentifier = taskIdentifier
        self.uuid = uuid
        self.trackerId = trackerId
        self.fileVersion = fileVersion
        self.transfer = transfer
        self.requestInfo = requestInfo
    }
    
    // MARK: DatabaseModel
    
    static func createTable(db: Connection) throws {
        try startCreateTable(db: db) { t in
            t.column(idField.description, primaryKey: true)
            t.column(taskIdentifierField.description)
            t.column(uuidField.description)
            t.column(trackerIdField.description)
            t.column(fileVersionField.description)
            t.column(transferField.description)
            t.column(requestInfoField.description)
        }
    }
    
    static func rowToModel(db: Connection, row: Row) throws -> NetworkCache {
        return try NetworkCache(db: db,
            id: row[Self.idField.description],
            taskIdentifier: row[Self.taskIdentifierField.description],
            uuid: row[Self.uuidField.description],
            trackerId: row[Self.trackerIdField.description],
            fileVersion: row[Self.fileVersionField.description],
            transfer: row[Self.transferField.description],
            requestInfo: row[Self.requestInfoField.description]
        )
    }
    
    func insert() throws {
        try doInsertRow(db: db, values:
            Self.taskIdentifierField.description <- taskIdentifier,
            Self.uuidField.description <- uuid,
            Self.trackerIdField.description <- trackerId,
            Self.fileVersionField.description <- fileVersion,
            Self.transferField.description <- transfer,
            Self.requestInfoField.description <- requestInfo
        )
    }
}






