//
//  UploadObjectTracker.swift
//  
//
//  Created by Christopher G Prince on 9/4/20.
//

import SQLite
import Foundation
import ServerShared
import iOSShared

// A record is added each time the SyncServer `queue` method is called.

class UploadObjectTracker: DatabaseModel {
    let db: Connection
    var id: Int64!
     
    static let fileGroupUUIDField = Field("fileGroupUUID", \M.fileGroupUUID)
    var fileGroupUUID: UUID
    
    // Is this the upload of the first versions of all of the tracked files? Or upload of vN versions? Note that, due to server design, an upload of a collection of files can't include both v0 and vN files. Note further that this can't be established until immediately prior to queuing the upload request(s) to the server because prior queued uploads for the same `fileGroupUUID` might not yet have completed.
    static let v0UploadField = Field("v0Upload", \M.v0Upload)
    var v0Upload: Bool?
    
    // Set for vN uploads, once all changes have successfully uploaded.
    static let deferredUploadIdField = Field("deferredUploadId", \M.deferredUploadId)
    var deferredUploadId: Int64?
    
    static let pushNotificationMessageField = Field("pushNotificationMessage", \M.pushNotificationMessage)
    var pushNotificationMessage: String?
    
    // These two `batch` fields must be the same for all N of N files being uploaded for a file group, N <= N.
    static let batchUUIDField = Field("batchUUID", \M.batchUUID)
    var batchUUID: UUID
    
    static let expiryInterval: TimeInterval = 60 * 60 * 2 // 2 hours
    static let batchExpiryIntervalField = Field("batchExpiryInterval", \M.batchExpiryInterval)
    var batchExpiryInterval:TimeInterval
    
    init(db: Connection,
        id: Int64! = nil,
        fileGroupUUID: UUID,
        v0Upload: Bool? = nil,
        batchUUID: UUID,
        batchExpiryInterval: TimeInterval,
        deferredUploadId: Int64? = nil,
        pushNotificationMessage: String? = nil) throws {
        
        self.db = db
        self.id = id
        self.fileGroupUUID = fileGroupUUID
        self.v0Upload = v0Upload
        self.deferredUploadId = deferredUploadId
        self.pushNotificationMessage = pushNotificationMessage
        self.batchUUID = batchUUID
        self.batchExpiryInterval = batchExpiryInterval
    }
    
    // MARK: DatabaseModel
    
    static func createTable(db: Connection) throws {
        try startCreateTable(db: db) { t in
            t.column(idField.description, primaryKey: true)
            t.column(fileGroupUUIDField.description)
            t.column(v0UploadField.description)
            t.column(deferredUploadIdField.description)
            t.column(pushNotificationMessageField.description)
            t.column(batchUUIDField.description)
            t.column(batchExpiryIntervalField.description)
        }
    }
    
    static func rowToModel(db: Connection, row: Row) throws -> UploadObjectTracker {
        return try UploadObjectTracker(db: db,
            id: row[Self.idField.description],
            fileGroupUUID: row[Self.fileGroupUUIDField.description],
            v0Upload: row[Self.v0UploadField.description],
            batchUUID: row[Self.batchUUIDField.description],
            batchExpiryInterval: row[Self.batchExpiryIntervalField.description],
            deferredUploadId: row[Self.deferredUploadIdField.description],
            pushNotificationMessage: row[Self.pushNotificationMessageField.description]
        )
    }
    
    func insert() throws {
        try doInsertRow(db: db, values:
            Self.fileGroupUUIDField.description <- fileGroupUUID,
            Self.v0UploadField.description <- v0Upload,
            Self.deferredUploadIdField.description <- deferredUploadId,
            Self.pushNotificationMessageField.description <- pushNotificationMessage,
            Self.batchUUIDField.description <- batchUUID,
            Self.batchExpiryIntervalField.description <- batchExpiryInterval
        )
    }
}

extension UploadObjectTracker {
    func dependentFileTrackers() throws -> [UploadFileTracker] {
        guard let id = id else {
            throw DatabaseModelError.noId
        }
        
        return try UploadFileTracker.fetch(db: db, where: id == UploadFileTracker.uploadObjectTrackerIdField.description)
    }
    
    static func dependentFileTrackers(forId id: Int64, db: Connection) throws -> [UploadFileTracker] {
        guard let objectTracker = try UploadObjectTracker.fetchSingleRow(db: db, where: id == UploadObjectTracker.idField.description) else {
            throw DatabaseModelError.notExactlyOneRowWithId
        }
    
        return try objectTracker.dependentFileTrackers()
    }
    
    struct UploadWithStatus {
        let object: UploadObjectTracker
        let files: [UploadFileTracker]
    }
    
    // Get all upload object trackers
    //  Get their dependent file trackers
    //    Check the status of *all* of these trackers: Do they match `status`?
    // Each returned `UploadWithStatus` will have an `UploadObjectTracker` with at least one file tracker.
    static func allUploadsWith(status: UploadFileTracker.Status, db: Connection) throws -> [UploadWithStatus] {
        var uploads = [UploadWithStatus]()
        let objectTrackers = try UploadObjectTracker.fetch(db: db)
        for objectTracker in objectTrackers {
            let fileTrackers = try objectTracker.dependentFileTrackers()
            let filtered = fileTrackers.filter {$0.status == status}
            if filtered.count == fileTrackers.count && filtered.count > 0 {
                uploads += [
                    UploadWithStatus(object: objectTracker, files: fileTrackers)
                ]
            }
        }
        
        return uploads
    }
    
    // Are there *any* dependent file trackers for a given file group that are currently having a specific status?
    static func anyUploadsWith(status: UploadFileTracker.Status, fileGroupUUID: UUID, db: Connection) throws -> Bool {
        let objectTrackers = try UploadObjectTracker.fetch(db: db, where: fileGroupUUID == UploadObjectTracker.fileGroupUUIDField.description)
        for objectTracker in objectTrackers {
            let fileTrackers = try objectTracker.dependentFileTrackers()
            let filtered = fileTrackers.filter {$0.status == status}
            if filtered.count > 0 {
                return true
            }
        }
        
        return false
    }
}

enum UploadObjectTrackerError: Error {
    case noObjectEntry
}

extension UploadObjectTracker {
    func getSharingGroup() throws -> UUID {
        guard let objectEntry = try DirectoryObjectEntry.fetchSingleRow(db: db, where: DirectoryObjectEntry.fileGroupUUIDField.description == fileGroupUUID) else {
            throw UploadObjectTrackerError.noObjectEntry
        }
        
        return objectEntry.sharingGroupUUID
    }
}
