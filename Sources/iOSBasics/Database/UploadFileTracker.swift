// Represents a file to be or being uploaded.

import SQLite
import Foundation
import ServerShared
import iOSShared

class UploadFileTracker: DatabaseModel, ExpiringTracker {
    enum UploadFileTrackerError: Error {
        case notExactlyOneMimeType
        case couldNotSetExpiry
        case noExpiryDate
    }
        
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
    
    static let mimeTypeField = Field("mimeType", \M.mimeType)
    var mimeType: MimeType
    
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
    
    static let appMetaDataField = Field("appMetaData", \M.appMetaData)
    var appMetaData: String?

    static let uploadIndexField = Field("uploadIndex", \M.uploadIndex)
    var uploadIndex: Int32
    
    static let uploadCountField = Field("uploadCount", \M.uploadCount)
    var uploadCount: Int32
    
    // MIGRATION: 5/30/21
    static let informAllButSelfField = Field("informAllButSelf", \M.informAllButSelf)
    var informAllButSelf: Bool?
    
    // MIGRATION: 8/2/21
    static let expiryField = Field("expiry", \M.expiry)
    // When should the upload be retried if it is in an `uploading` state and hasn't yet been completed? This is optional because it will be nil until the state of the `UploadFileTracker` changes to `.uploading`.
    var expiry: Date?
    
    // MIGRATION: 8/7/21
    // NetworkCache Id, if uploading.
    static let networkCacheIdField = Field("networkCacheId", \M.networkCacheId)
    var networkCacheId: Int64?
    
    init(db: Connection,
        id: Int64! = nil,
        uploadObjectTrackerId: Int64,
        status: Status,
        fileUUID: UUID,
        mimeType: MimeType,
        fileVersion: FileVersionInt?,
        localURL:URL?,
        goneReason: GoneReason?,
        uploadCopy: Bool,
        checkSum: String?,
        appMetaData: String?,
        uploadIndex: Int32,
        uploadCount: Int32,
        informAllButSelf: Bool?,
        expiry: Date?,
        networkCacheId: Int64? = nil) throws {

        self.db = db
        self.id = id
        self.uploadObjectTrackerId = uploadObjectTrackerId
        self.status = status
        self.fileUUID = fileUUID
        self.mimeType = mimeType
        self.fileVersion = fileVersion
        self.localURL = localURL
        self.goneReason = goneReason
        self.uploadCopy = uploadCopy
        self.checkSum = checkSum
        self.appMetaData = appMetaData
        self.uploadIndex = uploadIndex
        self.uploadCount = uploadCount
        self.informAllButSelf = informAllButSelf
        self.expiry = expiry
        self.networkCacheId = networkCacheId
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
            t.column(appMetaDataField.description)
            t.column(mimeTypeField.description)
            t.column(uploadIndexField.description)
            t.column(uploadCountField.description)
            
            // MIGRATION, 5/30/21
            // t.column(informAllButSelfField.description)
            
            // MIGRATION, 8/2/21
            // t.column(expiryField.description)

            // MIGRATION, 8/7/21
            // t.column(networkCacheIdField.description)
        }
    }
    
    static func rowToModel(db: Connection, row: Row) throws -> UploadFileTracker {
        return try UploadFileTracker(db: db,
            id: row[Self.idField.description],
            uploadObjectTrackerId: row[Self.uploadObjectTrackerIdField.description],
            status: row[Self.statusField.description],
            fileUUID: row[Self.fileUUIDField.description],
            mimeType: row[Self.mimeTypeField.description],
            fileVersion: row[Self.fileVersionField.description],
            localURL: row[Self.localURLField.description],
            goneReason: row[Self.goneReasonField.description],
            uploadCopy: row[Self.uploadCopyField.description],
            checkSum: row[Self.checkSumField.description],
            appMetaData: row[Self.appMetaDataField.description],
            uploadIndex: row[Self.uploadIndexField.description],
            uploadCount: row[Self.uploadCountField.description],
            informAllButSelf: row[Self.informAllButSelfField.description],
            expiry: row[Self.expiryField.description],
            networkCacheId: row[Self.networkCacheIdField.description]
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
            Self.checkSumField.description <- checkSum,
            Self.appMetaDataField.description <- appMetaData,
            Self.mimeTypeField.description <- mimeType,
            Self.uploadIndexField.description <- uploadIndex,
            Self.uploadCountField.description <- uploadCount,
            Self.informAllButSelfField.description <- informAllButSelf,
            Self.expiryField.description <- expiry,
            Self.networkCacheIdField.description <- networkCacheId
        )
    }
}

// MARK: Migrations

extension UploadFileTracker {
    // MARK: Metadata migrations
    
    static func migration_2021_5_30(db: Connection) throws {
        try addColumn(db: db, column: informAllButSelfField.description)
    }

    static func migration_2021_8_2(db: Connection) throws {
        // 9/9/21; I'm not going to throw an error on failing this because I believe Rod is now in a state where this has been applied, but the expiry dates for uploading file trackers haven't yet been applied. And other users don't yet have this migration.
        try? addColumn(db: db, column: expiryField.description)
    }

    static func migration_2021_8_7(db: Connection) throws {
        // 9/10/21; Not sure why, but this is now crashing for Rod. Not throwing error.
        try? addColumn(db: db, column: networkCacheIdField.description)
    }
    
    // MARK: Content migrations
    
    static func migration_2021_8_2_updateUploads(configuration: ExpiryConfigurable, db: Connection) throws {
        // For all upload file trackers that are in an .uploading state, give them an expiry date.
        let uploadingFileTrackers = try fetch(db: db, where: UploadFileTracker.statusField.description == .uploading)
        for uploadingFileTracker in uploadingFileTrackers {
            let expiryDate = try expiryDate(expiryDuration: configuration.expiryDuration)
            try uploadingFileTracker.update(setters: UploadFileTracker.expiryField.description <- expiryDate)
        }
    }

    // This is a specific fix for Rod for https://github.com/SyncServerII/Neebla/issues/25#issuecomment-898773102
    static func migration_2021_8_13_Rod(currentUserId: UserId?, db: Connection) throws {
        
        let makeChangeForUserId: UserId = 3 // Rod's user Id.
        
        guard currentUserId == makeChangeForUserId else {
            logger.notice("migration_2021_8_13_Rod: Didn't have needed userId: \(String(describing: currentUserId))")
            return
        }
        
        let changes:[(fileUUID: UUID, newURL: URL)] = [
            (UUID(uuidString: "5E0531A2-6E86-435E-859B-D4A13F3C7F54")!,
                URL(fileURLWithPath: "/private/var/mobile/Containers/Shared/AppGroup/8D71FCAB-402E-4820-843E-564B0BEAD8CD/Documents/objects/Neebla.B3B4EDB9-F2C0-430F-B4E5-2F8BFA6AFAC2.url")),
                
            (UUID(uuidString: "B22449D3-BCAB-4E93-8B4A-74DCFC2E6C34")!, URL(fileURLWithPath: "/private/var/mobile/Containers/Shared/AppGroup/8D71FCAB-402E-4820-843E-564B0BEAD8CD/Documents/objects/Neebla.66242889-39CF-41C6-BF33-99FB6D8FC0FF.jpg")),
            
            (UUID(uuidString: "C0F990AD-8E46-46AE-A97B-3D3270F0EF78")!, URL(fileURLWithPath: "/private/var/mobile/Containers/Shared/AppGroup/8D71FCAB-402E-4820-843E-564B0BEAD8CD/Documents/objects/Neebla.7AECB75A-ED5C-4E61-B36D-82E274CD7485.jpg")),
            
            (UUID(uuidString: "75C95CC9-BF03-4B1D-AD2D-C5B1BE30AD11")!, URL(fileURLWithPath: "/private/var/mobile/Containers/Shared/AppGroup/8D71FCAB-402E-4820-843E-564B0BEAD8CD/Documents/objects/Neebla.8731E8E6-538A-4B8B-A00E-2B46E409160A.jpg"))
        ]
        
        func fixOneFile(fileUUID: UUID, updatedLocalURL: URL) throws {
            guard let fileTracker = try UploadFileTracker.fetchSingleRow(db: db, where: UploadFileTracker.fileUUIDField.description == fileUUID) else {
                throw DatabaseError.notExactlyOneRow
            }
            
            try fileTracker.update(setters: UploadFileTracker.localURLField.description <- updatedLocalURL)
        }
        
        for change in changes {
            try fixOneFile(fileUUID: change.fileUUID, updatedLocalURL: change.newURL)
        }
    }
    
#if DEBUG
    static func allMigrations(configuration: ExpiryConfigurable, updateUploads: Bool = true, db: Connection) throws {
        // MARK: Metadata
        try migration_2021_5_30(db: db)
        try migration_2021_8_2(db: db)
        try migration_2021_8_7(db: db)
        
        // MARK: Content
        try migration_2021_8_2_updateUploads(configuration: configuration, db: db)
    }
#endif
}

extension UploadFileTracker {        
    // Creates an `UploadFileTracker` and copies data from the file's UploadableDataSource to a temporary file location if needed.
    // The returned `UploadFileTracker` has been inserted into the database.
    // The objectTrackerId is the id of the UploadObjectTracker for this file.
    static func create(file: UploadableFile, objectModel: DeclaredObjectModel, cloudStorageType: CloudStorageType, objectTrackerId: Int64, uploadIndex: Int32, uploadCount: Int32, informAllButSelf: Bool?, config: Configuration.TemporaryFiles, hashingManager: HashingManager, db: Connection) throws -> UploadFileTracker {
        let url: URL
        switch file.dataSource {
        case .data(let data):
            url = try FileUtils.copyDataToNewTemporary(data: data, config: config)
        case .copy(let copyURL):
            url = try FileUtils.copyFileToNewTemporary(original: copyURL, config: config)
        case .immutable(let immutableURL):
            url = immutableURL
        }
        
        let checkSum = try hashingManager.hashFor(cloudStorageType: cloudStorageType).hash(forURL: url)
        
        let uploadMimeType: MimeType
        
        if let mimeType = file.mimeType {
            uploadMimeType = mimeType
        }
        else {
            let fileDeclaration = try objectModel.getFile(with: file.fileLabel)
            guard fileDeclaration.mimeTypes.count == 1,
                let mimeType = fileDeclaration.mimeTypes.first else {
                throw UploadFileTrackerError.notExactlyOneMimeType
            }
            uploadMimeType = mimeType
        }
                
        let fileTracker = try UploadFileTracker(db: db, uploadObjectTrackerId: objectTrackerId, status: .notStarted, fileUUID: file.uuid, mimeType: uploadMimeType, fileVersion: nil, localURL: url, goneReason: nil, uploadCopy: file.dataSource.isCopy, checkSum: checkSum, appMetaData: file.appMetaData, uploadIndex: uploadIndex, uploadCount: uploadCount, informAllButSelf: informAllButSelf, expiry: nil)
        try fileTracker.insert()
        
        return fileTracker
    }
}

extension UploadFileTracker: BackgroundCacheFileTracker {
    func update(networkCacheId: Int64) throws {
        try update(setters: UploadFileTracker.networkCacheIdField.description <- networkCacheId)
    }
}
