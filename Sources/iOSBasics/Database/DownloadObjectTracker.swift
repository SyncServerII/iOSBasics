// Represents a collection of files to be or being downloaded.

import SQLite
import Foundation
import ServerShared
import iOSShared

class DownloadObjectTracker: DatabaseModel {
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
            
            // Not making this unique because we're allowing queueing of downloads with the same file group. They won't dowload in parallel though.
            t.column(fileGroupUUIDField.description)
        }
    }
    
    static func rowToModel(db: Connection, row: Row) throws -> DownloadObjectTracker {
        return try DownloadObjectTracker(db: db,
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

extension DownloadObjectTracker {
    // Are there *any* dependent file trackers for a given file group that are currently having a specific status?
    static func anyDownloadsWith(status: DownloadFileTracker.Status, fileGroupUUID: UUID, db: Connection) throws -> Bool {
        let objectTrackers = try DownloadObjectTracker.fetch(db: db, where: fileGroupUUID == DownloadObjectTracker.fileGroupUUIDField.description)
        for objectTracker in objectTrackers {
            let fileTrackers = try objectTracker.dependentFileTrackers()
            let filtered = fileTrackers.filter {$0.status == status}
            if filtered.count > 0 {
                return true
            }
        }
        
        return false
    }
    
    struct DownloadWithStatus {
        let object: DownloadObjectTracker
        let files: [DownloadFileTracker]
    }
    
    // Get all download object trackers
    //  Get their dependent file trackers
    //    Check the status of *all* of these trackers: Do they match `status`?
    // Each returned `DownloadWithStatus` will have an `DownloadObjectTracker` with at least one file tracker.
    static func allDownloadsWith(status: DownloadFileTracker.Status, db: Connection) throws -> [DownloadWithStatus] {
        var uploads = [DownloadWithStatus]()
        let objectTrackers = try DownloadObjectTracker.fetch(db: db)
        for objectTracker in objectTrackers {
            let fileTrackers = try objectTracker.dependentFileTrackers()
            let filtered = fileTrackers.filter {$0.status == status}
            if filtered.count == fileTrackers.count && filtered.count > 0 {
                uploads += [
                    DownloadWithStatus(object: objectTracker, files: fileTrackers)
                ]
            }
        }
        
        return uploads
    }
}
