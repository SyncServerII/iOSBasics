
import SQLite
import Foundation
import ServerShared
import iOSShared

// Represents a file or file group to be or being deleted on the server. Only a single tracker model object for deletion because we just send a single request to the server-- with a fileUUID or with a fileGroupUUID.

class UploadDeletionTracker: DatabaseModel {
    enum UploadDeletionTrackerError: Error {
        case badDeletionType
        case noObjectEntry
    }
    
    let db: Connection
    var id: Int64!
    
    // This will be either a fileUUID or fileGroupUUID, depending on deletionType, below.
    static let uuidField = Field("uuid", \M.uuid)
    var uuid: UUID
    
    enum DeletionType : String {
        case fileGroupUUID
        
        @available(*, deprecated)
        case fileUUID
    }
    
    // The type of uuid used above.
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

    static let pushNotificationMessageField = Field("pushNotificationMessage", \M.pushNotificationMessage)
    var pushNotificationMessage: String?
    
    init(db: Connection,
        id: Int64! = nil,
        uuid: UUID,
        deletionType: DeletionType,
        deferredUploadId: Int64? = nil,
        status: Status,
        pushNotificationMessage: String? = nil) throws {

        self.db = db
        self.id = id
        self.uuid = uuid
        self.deletionType = deletionType
        self.deferredUploadId = deferredUploadId
        self.status = status
        self.pushNotificationMessage = pushNotificationMessage
    }
    
    // MARK: DatabaseModel
    
    static func createTable(db: Connection) throws {
        try startCreateTable(db: db) { t in
            t.column(idField.description, primaryKey: true)
            t.column(deferredUploadIdField.description)
            t.column(statusField.description)
            t.column(uuidField.description)
            t.column(deletionTypeField.description)
            t.column(pushNotificationMessageField.description)
        }
    }
    
    static func rowToModel(db: Connection, row: Row) throws -> UploadDeletionTracker {
        return try UploadDeletionTracker(db: db,
            id: row[Self.idField.description],
            uuid: row[Self.uuidField.description],
            deletionType: row[Self.deletionTypeField.description],
            deferredUploadId: row[Self.deferredUploadIdField.description],
            status: row[Self.statusField.description],
            pushNotificationMessage: row[Self.pushNotificationMessageField.description]
        )
    }
    
    func insert() throws {
        try doInsertRow(db: db, values:
            Self.uuidField.description <- uuid,
            Self.deletionTypeField.description <- deletionType,
            Self.statusField.description <- status,
            Self.deferredUploadIdField.description <- deferredUploadId,
            Self.pushNotificationMessageField.description <- pushNotificationMessage
        )
    }
}

extension UploadDeletionTracker {
    func getSharingGroup() throws -> UUID {
        guard deletionType == .fileGroupUUID else {
            throw UploadDeletionTrackerError.badDeletionType
        }
        
        guard let objectEntry = try DirectoryObjectEntry.fetchSingleRow(db: db, where: DirectoryObjectEntry.fileGroupUUIDField.description == uuid) else {
            throw UploadDeletionTrackerError.noObjectEntry
        }
        
        return objectEntry.sharingGroupUUID
    }
}
