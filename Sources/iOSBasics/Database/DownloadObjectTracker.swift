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
    //    Check the status of these trackers: Do they match `status`?
    // Each returned `DownloadWithStatus` will have an `DownloadObjectTracker` with at least one file tracker.
    enum StatusCheckScope {
        case all // all dependent trackers must have the given status
        case some // > 0 dependent trackers must have the given status
    }
    
    static func downloadsWith(status: DownloadFileTracker.Status, scope: StatusCheckScope, db: Connection) throws -> [DownloadWithStatus] {
        var uploads = [DownloadWithStatus]()
        let objectTrackers = try DownloadObjectTracker.fetch(db: db)
        for objectTracker in objectTrackers {
            let fileTrackers = try objectTracker.dependentFileTrackers()
            let filtered = fileTrackers.filter {$0.status == status}
            
            switch scope {
            case .all:
                if filtered.count == fileTrackers.count && filtered.count > 0 {
                    uploads += [
                        DownloadWithStatus(object: objectTracker, files: fileTrackers)
                    ]
                }
                
            case .some:
                if filtered.count > 0 {
                    uploads += [
                        DownloadWithStatus(object: objectTracker, files: filtered)
                    ]
                }
            }
        }
        
        return uploads
    }
    
    static let maxRetriesPerFile = 5
    
    // Check if the number of download retries for the file has been exceeded. If yes, then the `DownloadFileTracker` is removed. If there are no more, then remove the object tracker too.
    static func removeIfTooManyRetries(fileTracker: DownloadFileTracker, db: Connection) throws -> DownloadObjectTracker {
        if fileTracker.numberRetries >= maxRetriesPerFile {
            try fileTracker.delete()
        }
        
        guard let objectTracker = try DownloadObjectTracker.fetchSingleRow(db: db, where: DownloadObjectTracker.idField.description == fileTracker.downloadObjectTrackerId) else {
            throw DatabaseError.noObject
        }
        
        let fileTrackers = try objectTracker.dependentFileTrackers()
        if fileTrackers.count == 0 {
            try objectTracker.delete()
        }
        
        return objectTracker
    }
}
