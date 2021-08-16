// Represents a file to be or being downloaded.

import SQLite
import Foundation
import ServerShared
import iOSShared

class DownloadFileTracker: DatabaseModel, ExpiringTracker, BackgroundCacheFileTracker {
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
    
    // MIGRATION: 8/15/21
    static let expiryField = Field("expiry", \M.expiry)
    // When should the download be retried if it is in an `downloading` state and hasn't yet been completed? This is optional because it will be nil until the state of the `DownloadFileTracker` changes to `.downloading`.
    var expiry: Date?
    
    // MIGRATION: 8/15/21
    // NetworkCache Id, if downloading.
    static let networkCacheIdField = Field("networkCacheId", \M.networkCacheId)
    var networkCacheId: Int64?
    
    init(db: Connection,
        id: Int64! = nil,
        downloadObjectTrackerId: Int64,
        status: Status,
        numberRetries: Int = 0,
        fileUUID: UUID,
        fileVersion: FileVersionInt,
        localURL:URL?,
        appMetaData: String? = nil,
        expiry: Date? = nil,
        networkCacheId: Int64? = nil) throws {

        self.db = db
        self.id = id
        self.downloadObjectTrackerId = downloadObjectTrackerId
        self.status = status
        self.numberRetries = numberRetries
        self.fileUUID = fileUUID
        self.fileVersion = fileVersion
        self.localURL = localURL
        self.appMetaData = appMetaData
        self.expiry = expiry
        self.networkCacheId = networkCacheId
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
            
            // Migration
            // t.column(expiryField.description)
            
            // Migration
            // t.column(networkCacheIdField.description)
        }
    }

    static func rowToModel(db: Connection, row: Row) throws -> DownloadFileTracker {
        return try DownloadFileTracker(db: db,
            id: row[Self.idField.description],
            downloadObjectTrackerId: row[Self.downloadObjectTrackerIdField.description],
            status: row[Self.statusField.description],
            numberRetries: row[Self.numberRetriesField.description],
            fileUUID: row[Self.fileUUIDField.description],
            fileVersion: row[Self.fileVersionField.description],
            localURL: row[Self.localURLField.description],
            appMetaData: row[Self.appMetaDataField.description],
            expiry: row[Self.expiryField.description],
            networkCacheId: row[Self.networkCacheIdField.description]
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
            Self.appMetaDataField.description <- appMetaData,
            Self.expiryField.description <- expiry,
            Self.networkCacheIdField.description <- networkCacheId
        )
    }
}

// MARK: Migrations

extension DownloadFileTracker {
    // MARK: Metadata migrations

    static func migration_2021_5_8(db: Connection) throws {
        try addColumn(db: db, column: appMetaDataField.description)
    }
    
    static func migration_2021_8_15_a(db: Connection) throws {
        try addColumn(db: db, column: expiryField.description)
    }
    
    static func migration_2021_8_15_b(db: Connection) throws {
        try addColumn(db: db, column: networkCacheIdField.description)
    }
    
    // MARK: Content migrations
    
    static func migration_2021_8_15_updateExpiries(configuration: ExpiryConfigurable, db: Connection) throws {
        // For download file trackers that are in an .downloading state, give them an expiry date.
        let fileTrackers = try fetch(db: db, where: DownloadFileTracker.statusField.description == .downloading)
        let expiryDate = try expiryDate(expiryDuration: configuration.expiryDuration)

        for fileTracker in fileTrackers {
            try fileTracker.update(setters: DownloadFileTracker.expiryField.description <- expiryDate)
        }
    }
    
#if DEBUG
    static func allMigrations(db: Connection) throws {
        try migration_2021_5_8(db: db)
        try migration_2021_8_15_a(db: db)
        try migration_2021_8_15_b(db: db)
    }
#endif
}

extension DownloadFileTracker {
    func update(networkCacheId: Int64) throws {
        try update(setters: DownloadFileTracker.networkCacheIdField.description <- networkCacheId)
    }
    
    func reset() throws {
        try update(setters:
            DownloadFileTracker.statusField.description <- .notStarted,
            DownloadFileTracker.expiryField.description <- nil,
            DownloadFileTracker.numberRetriesField.description <- numberRetries + 1)
        
        if let localURL = localURL {
            logger.debug("Removing file: \(localURL)")
            try FileManager.default.removeItem(at: localURL)
            try update(setters: DownloadFileTracker.localURLField.description <- nil)
        }
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
