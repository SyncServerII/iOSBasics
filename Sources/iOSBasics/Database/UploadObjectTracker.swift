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
    
    enum Scope {
        case any
        case all
    }
    
    // Get matching upload object trackers
    // First, get their dependent file trackers
    //  For scope == .all: Does the predicate match all of these trackers?
    //  For scope == .any: Does the predicate match any of these trackers?
    // Each returned `UploadWithStatus` will have an `UploadObjectTracker` with at least one file tracker.
    static func uploadsMatching(filePredicate: (UploadFileTracker)->(Bool), scope: Scope, whereObjects: SQLite.Expression<Bool>? = nil, db: Connection) throws -> [UploadWithStatus] {
        var uploads = [UploadWithStatus]()
        let objectTrackers = try UploadObjectTracker.fetch(db: db, where: whereObjects)
        for objectTracker in objectTrackers {
            let fileTrackers = try objectTracker.dependentFileTrackers()
            let filteredFileTrackers = fileTrackers.filter { filePredicate($0) }
            
            var scopeConstraint: Bool
            switch scope {
            case .any:
                scopeConstraint = true
            case .all:
                scopeConstraint = filteredFileTrackers.count == fileTrackers.count
            }
            
            if scopeConstraint && filteredFileTrackers.count > 0 {
                uploads += [
                    UploadWithStatus(object: objectTracker, files: filteredFileTrackers)
                ]
            }
        }
        
        return uploads
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

// MARK: Figure out what uploads need to be started next.
extension UploadObjectTracker {
    static func toBeStartedNext(db: Connection) throws -> [UploadObjectTracker.UploadWithStatus] {
    
        // Basic strategy:
        // 1) Serialize uploads for specific file groups. I.e., we don't allow parallel uploads of different `UploadObjectTracker`'s for the same file group. This protects us from, for example, uploading vN files at the same time as v0 files for the same file group.
        // 2) If we have multiple .notStarted `UploadObjectTracker`'s for the same file group, v0 uploads must be uploaded first. This takes into account v0 uploads that have failed and that have to be restarted.
        
        var uploadsToStart = [UploadObjectTracker.UploadWithStatus]()
        
        // These are the uploads that haven't been started yet, and that we may be starting with this call.
        let notStartedUploads:[UploadObjectTracker.UploadWithStatus] = try UploadObjectTracker.uploadsMatching(filePredicate: {$0.status == .notStarted}, scope: .any, db: db)
        
        let fileGroups = Partition.array(notStartedUploads, using: \UploadObjectTracker.UploadWithStatus.object.fileGroupUUID)

        for fileGroup in fileGroups {
            guard fileGroup.count > 0 else {
                logger.error("Empty file group array")
                continue
            }
            
            // Are there any uploads currently in progress for the current file group? (We are serializing uploads for `UploadObjectTracker`'s for each file group).
            let inProgress = try UploadObjectTracker.uploadsMatching(filePredicate: {$0.status == .uploading}, scope: .any, whereObjects: UploadObjectTracker.fileGroupUUIDField.description == fileGroup[0].object.fileGroupUUID, db: db)
            guard inProgress.count == 0 else {
                continue
            }
            
            // Only start one new upload per file group (really, a set of files in a single `UploadObjectTracker`). And prioritize v0 uploads if there are any.
            var toStart: UploadObjectTracker.UploadWithStatus?
            
            let v0Uploads = fileGroup.filter { $0.object.v0Upload == true }
            if v0Uploads.count > 0 {
                toStart = v0Uploads[0]
            }
            else if fileGroup.count > 0 {
                toStart = fileGroup[0]
            }
            
            if let toStart = toStart {
                uploadsToStart += [toStart]
            }
        }
        
        return uploadsToStart
    }
}
