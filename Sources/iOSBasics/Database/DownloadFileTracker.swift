// Represents a file to be or being downloaded.

import SQLite
import Foundation
import ServerShared
import iOSShared

class DownloadFileTracker: DatabaseModel {
    let db: Connection
    var id: Int64!
    
    enum Status : String {
        case notStarted
        case downloading
        
        // This is for both successfully downloaded files and files that cannot be downloaded due to a gone response.
        case downloaded
    }

    static let downloadObjectTrackerIdField = Field("downloadObjectTrackerId", \M.downloadObjectTrackerId)
    var downloadObjectTrackerId: Int64
    
    static let fileUUIDField = Field("fileUUID", \M.fileUUID)
    var fileUUID: UUID
    
    static let statusField = Field("status", \M.status)
    var status: Status

    static let fileVersionField = Field("fileVersion", \M.fileVersion)
    var fileVersion: FileVersionInt

    // The url of the downloaded file.
    static let localURLField = Field("localURL", \M.localURL)
    var localURL:URL!
    
    init(db: Connection,
        id: Int64! = nil,
        downloadObjectTrackerId: Int64,
        status: Status,
        fileUUID: UUID,
        fileVersion: FileVersionInt,
        localURL:URL?) throws {

        self.db = db
        self.id = id
        self.downloadObjectTrackerId = downloadObjectTrackerId
        self.status = status
        self.fileUUID = fileUUID
        self.fileVersion = fileVersion
        self.localURL = localURL
    }
    
    // MARK: DatabaseModel
    
    static func createTable(db: Connection) throws {
        try startCreateTable(db: db) { t in
            t.column(idField.description, primaryKey: true)
            t.column(downloadObjectTrackerIdField.description)
            t.column(statusField.description)
            
            // Not making this unique because allowing queueing (but not parallel downloading) of the same file group.
            t.column(fileUUIDField.description)
            
            t.column(fileVersionField.description)
            t.column(localURLField.description)
        }
    }
    
    static func rowToModel(db: Connection, row: Row) throws -> DownloadFileTracker {
        return try DownloadFileTracker(db: db,
            id: row[Self.idField.description],
            downloadObjectTrackerId: row[Self.downloadObjectTrackerIdField.description],
            status: row[Self.statusField.description],
            fileUUID: row[Self.fileUUIDField.description],
            fileVersion: row[Self.fileVersionField.description],
            localURL: row[Self.localURLField.description]
        )
    }
    
    func insert() throws {
        try doInsertRow(db: db, values:
            Self.downloadObjectTrackerIdField.description <- downloadObjectTrackerId,
            Self.statusField.description <- status,
            Self.fileUUIDField.description <- fileUUID,
            Self.fileVersionField.description <- fileVersion,
            Self.localURLField.description <- localURL
        )
    }
}

extension DownloadObjectTracker {
    func dependentFileTrackers() throws -> [DownloadFileTracker] {
        guard let id = id else {
            throw DatabaseModelError.noId
        }
        
        return try DownloadFileTracker.fetch(db: db, where: id == DownloadFileTracker.downloadObjectTrackerIdField.description)
    }
}
