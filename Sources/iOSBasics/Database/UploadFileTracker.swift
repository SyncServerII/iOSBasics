// Represents a file to be or being uploaded.

import SQLite
import Foundation
import ServerShared

class UploadFileTracker: DatabaseModel {
    let db: Connection
    var id: Int64!
    
    enum Status : String {
        case notStarted
        case uploading
        
        // This is for both successfully uploaded files and files that cannot be uploaded due to a gone response. For vN files this just means the first stage of the upload has completed. The full deferred upload hasn't necessarily completed yet.
        case uploaded
    }

    static let uploadObjectTrackerIdField = Field("uploadObjectTrackerId", \M.uploadObjectTrackerId)
    var uploadObjectTrackerId: Int64
    
    static let fileUUIDField = Field("fileUUID", \M.fileUUID)
    var fileUUID: UUID
    
    static let statusField = Field("status", \M.status)
    var status: Status

    static let fileVersionField = Field("fileVersion", \M.fileVersion)
    var fileVersion: FileVersionInt?

    static let localURLField = Field("localURL", \M.localURL)
    var localURL:URL?
    
    static let goneReasonField = Field("goneReason", \M.goneReason)
    var goneReason: GoneReason?

    static let uploadCopyField = Field("uploadCopy", \M.uploadCopy)
    var uploadCopy: Bool
    
    static let checkSumField = Field("checkSum", \M.checkSum)
    var checkSum: String?
    
    init(db: Connection,
        id: Int64! = nil,
        uploadObjectTrackerId: Int64,
        status: Status,
        fileUUID: UUID,
        fileVersion: FileVersionInt?,
        localURL:URL?,
        goneReason: GoneReason?,
        uploadCopy: Bool,
        checkSum: String?) throws {

        self.db = db
        self.id = id
        self.uploadObjectTrackerId = uploadObjectTrackerId
        self.status = status
        self.fileUUID = fileUUID
        self.fileVersion = fileVersion
        self.localURL = localURL
        self.goneReason = goneReason
        self.uploadCopy = uploadCopy
        self.checkSum = checkSum
    }
    
    // MARK: DatabaseModel
    
    static func createTable(db: Connection) throws {
        try startCreateTable(db: db) { t in
            t.column(idField.description, primaryKey: true)
            t.column(uploadObjectTrackerIdField.description)
            t.column(statusField.description)
            t.column(fileUUIDField.description)
            t.column(fileVersionField.description)
            t.column(localURLField.description)
            t.column(goneReasonField.description)
            t.column(uploadCopyField.description)
            t.column(checkSumField.description)
        }
    }
    
    static func rowToModel(db: Connection, row: Row) throws -> UploadFileTracker {
        return try UploadFileTracker(db: db,
            id: row[Self.idField.description],
            uploadObjectTrackerId: row[Self.uploadObjectTrackerIdField.description],
            status: row[Self.statusField.description],
            fileUUID: row[Self.fileUUIDField.description],
            fileVersion: row[Self.fileVersionField.description],
            localURL: row[Self.localURLField.description],
            goneReason: row[Self.goneReasonField.description],
            uploadCopy: row[Self.uploadCopyField.description],
            checkSum: row[Self.checkSumField.description]
        )
    }
    
    func insert() throws {
        try doInsertRow(db: db, values:
            Self.uploadObjectTrackerIdField.description <- uploadObjectTrackerId,
            Self.statusField.description <- status,
            Self.fileUUIDField.description <- fileUUID,
            Self.fileVersionField.description <- fileVersion,
            Self.localURLField.description <- localURL,
            Self.goneReasonField.description <- goneReason,
            Self.uploadCopyField.description <- uploadCopy,
            Self.checkSumField.description <- checkSum
        )
    }
}
