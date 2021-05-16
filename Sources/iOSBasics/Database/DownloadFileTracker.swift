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
    
    // The number of times that the download has failed, and has been restarted.
    static let numberRetriesField = Field("numberRetries", \M.numberRetries)
    var numberRetries: Int

    static let fileVersionField = Field("fileVersion", \M.fileVersion)
    var fileVersion: FileVersionInt

    // The url of the downloaded file.
    static let localURLField = Field("localURL", \M.localURL)
    var localURL:URL!
    
    // New as of 5/8/21; Migration needed.
    static let appMetaDataField = Field("appMetaData", \M.appMetaData)
    var appMetaData: String?
    
    init(db: Connection,
        id: Int64! = nil,
        downloadObjectTrackerId: Int64,
        status: Status,
        numberRetries: Int = 0,
        fileUUID: UUID,
        fileVersion: FileVersionInt,
        localURL:URL?,
        appMetaData: String? = nil) throws {

        self.db = db
        self.id = id
        self.downloadObjectTrackerId = downloadObjectTrackerId
        self.status = status
        self.numberRetries = numberRetries
        self.fileUUID = fileUUID
        self.fileVersion = fileVersion
        self.localURL = localURL
        self.appMetaData = appMetaData
    }
    
    // MARK: DatabaseModel
    
    static func createTable(db: Connection) throws {
        try startCreateTable(db: db) { t in
            t.column(idField.description, primaryKey: true)
            t.column(downloadObjectTrackerIdField.description)
            t.column(statusField.description)
            t.column(numberRetriesField.description)
            
            // Not making this unique because allowing queueing (but not parallel downloading) of the same file group.
            t.column(fileUUIDField.description)
            
            t.column(fileVersionField.description)
            t.column(localURLField.description)
            
            // Added in migration_2021_5_8
            // t.column(appMetaDataField.description)
        }
    }
    
    static func migration_2021_5_8(db: Connection) throws {
        try addColumn(db: db, column: appMetaDataField.description)
    }
    
#if DEBUG
    static func allMigrations(db: Connection) throws {
        try migration_2021_5_8(db: db)
    }
#endif

    static func rowToModel(db: Connection, row: Row) throws -> DownloadFileTracker {
        return try DownloadFileTracker(db: db,
            id: row[Self.idField.description],
            downloadObjectTrackerId: row[Self.downloadObjectTrackerIdField.description],
            status: row[Self.statusField.description],
            numberRetries: row[Self.numberRetriesField.description],
            fileUUID: row[Self.fileUUIDField.description],
            fileVersion: row[Self.fileVersionField.description],
            localURL: row[Self.localURLField.description],
            appMetaData: row[Self.appMetaDataField.description]
        )
    }
    
    func insert() throws {
        try doInsertRow(db: db, values:
            Self.downloadObjectTrackerIdField.description <- downloadObjectTrackerId,
            Self.statusField.description <- status,
            Self.numberRetriesField.description <- numberRetries,
            Self.fileUUIDField.description <- fileUUID,
            Self.fileVersionField.description <- fileVersion,
            Self.localURLField.description <- localURL,
            Self.appMetaDataField.description <- appMetaData
        )
    }
}

extension DownloadFileTracker {
    // Returns the `DownloadFileTracker` corresponding to the fileUUID and objectTrackerId.
    static func reset(fileUUID: String?, objectTrackerId: Int64, db: Connection) throws -> DownloadFileTracker {
        guard let fileUUIDString = fileUUID,
            let fileUUID = try UUID.from(fileUUIDString) else {
            throw SyncServerError.internalError("UUID conversion failed")
        }
        
        guard let fileTracker =
            try DownloadFileTracker.fetchSingleRow(db: db, where:
                DownloadFileTracker.downloadObjectTrackerIdField.description == objectTrackerId &&
                DownloadFileTracker.fileUUIDField.description == fileUUID) else {
            throw SyncServerError.internalError("Nil DownloadFileTracker")
        }
        
        try fileTracker.update(setters: DownloadFileTracker.statusField.description <- .notStarted,
            DownloadFileTracker.numberRetriesField.description <- fileTracker.numberRetries + 1)
        
        if let localURL = fileTracker.localURL {
            logger.debug("Removing file: \(localURL)")
            try FileManager.default.removeItem(at: localURL)
            try fileTracker.update(setters: DownloadFileTracker.localURLField.description <- nil)
        }
        
        return fileTracker
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
