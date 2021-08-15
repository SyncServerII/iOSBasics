
import SQLite
import Foundation
import ServerShared
import iOSShared

// Represents a file or file group to be or being deleted on the server. Only a single tracker model object for deletion because we just send a single request to the server-- with a fileUUID or with a fileGroupUUID.

class UploadDeletionTracker: DatabaseModel, BackgroundCacheFileTracker {
    enum UploadDeletionTrackerError: Error {
        case badDeletionType
        case noObjectEntry
        case couldNotSetExpiry
        case noExpiryDate
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
    
    // MIGRATION: 8/13/21
    static let expiryField = Field("expiry", \M.expiry)
    // When should the upload deletion be retried if it is in an `deleting` state and hasn't yet been completed? This is optional because it will be nil until the state of the `UploadDeletionTracker` changes to `.deleting`.
    var expiry: Date?
    
    // MIGRATION: 8/14/21
    // NetworkCache Id, if deleting.
    static let networkCacheIdField = Field("networkCacheId", \M.networkCacheId)
    var networkCacheId: Int64?
    
    init(db: Connection,
        id: Int64! = nil,
        uuid: UUID,
        deletionType: DeletionType,
        deferredUploadId: Int64? = nil,
        status: Status,
        pushNotificationMessage: String? = nil,
        expiry: Date? = nil,
        networkCacheId: Int64? = nil) throws {

        self.db = db
        self.id = id
        self.uuid = uuid
        self.deletionType = deletionType
        self.deferredUploadId = deferredUploadId
        self.status = status
        self.pushNotificationMessage = pushNotificationMessage
        self.expiry = expiry
        self.networkCacheId = networkCacheId
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
            
            // MIGRATION, 8/13/21
            // t.column(expiryField.description)

            // MIGRATION, 8/14/21
            // t.column(networkCacheIdField.description)
        }
    }
    
    static func rowToModel(db: Connection, row: Row) throws -> UploadDeletionTracker {
        return try UploadDeletionTracker(db: db,
            id: row[Self.idField.description],
            uuid: row[Self.uuidField.description],
            deletionType: row[Self.deletionTypeField.description],
            deferredUploadId: row[Self.deferredUploadIdField.description],
            status: row[Self.statusField.description],
            pushNotificationMessage: row[Self.pushNotificationMessageField.description],
            expiry: row[Self.expiryField.description],
            networkCacheId: row[Self.networkCacheIdField.description]
        )
    }
    
    func insert() throws {
        try doInsertRow(db: db, values:
            Self.uuidField.description <- uuid,
            Self.deletionTypeField.description <- deletionType,
            Self.statusField.description <- status,
            Self.deferredUploadIdField.description <- deferredUploadId,
            Self.pushNotificationMessageField.description <- pushNotificationMessage,
            Self.expiryField.description <- expiry,
            Self.networkCacheIdField.description <- networkCacheId
        )
    }
}

// MARK: Migrations

extension UploadDeletionTracker {
    // MARK: Metadata migrations

    static func migration_2021_8_14_a(db: Connection) throws {
        try addColumn(db: db, column: expiryField.description)
    }
    
    static func migration_2021_8_14_b(db: Connection) throws {
        try addColumn(db: db, column: networkCacheIdField.description)
    }
    
    // MARK: Content migrations
    
    static func migration_2021_8_14_updateExpiries(configuration: UploadConfigurable, db: Connection) throws {
        // For all upload deletion trackers that are in a .deleting state, give them an expiry date.
        let deletionTrackers = try fetch(db: db, where: UploadDeletionTracker.statusField.description == .deleting)
        let expiryDate = try expiryDate(uploadExpiryDuration: configuration.uploadExpiryDuration)
        
        for deletionTracker in deletionTrackers {
            try deletionTracker.update(setters: UploadDeletionTracker.expiryField.description <- expiryDate)
        }
    }
    
#if DEBUG
    static func allMigrations(configuration: UploadConfigurable, updateUploads: Bool = true, db: Connection) throws {
        // MARK: Metadata
        try migration_2021_8_14_a(db: db)
        try migration_2021_8_14_b(db: db)
        
        // MARK: Content
        try migration_2021_8_14_updateExpiries(configuration: configuration, db: db)
    }
#endif
}

extension UploadDeletionTracker {
    func update(networkCacheId: Int64) throws {
        try update(setters: UploadDeletionTracker.networkCacheIdField.description <- networkCacheId)
    }
    
    static func expiryDate(uploadExpiryDuration: TimeInterval) throws -> Date {
        let calendar = Calendar.current
        guard let expiryDate = calendar.date(byAdding: .second, value: Int(uploadExpiryDuration), to: Date()) else {
            throw UploadDeletionTrackerError.couldNotSetExpiry
        }
        
        return expiryDate
    }
    
    // Has the `expiry` Date of the UploadDeletionTracker expired? Assumes that this UploadDeletionTracker is in an .deleting state (and thus has a non-nil `expiry`) and throws an error if the `expiry` Date is nil.
    func hasExpired() throws -> Bool {
        guard let expiry = expiry else {
            throw UploadDeletionTrackerError.noExpiryDate
        }
        
        return expiry <= Date()
    }
    
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
