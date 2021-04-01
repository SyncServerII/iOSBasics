// Represents a file to be or being uploaded.

import SQLite
import Foundation
import ServerShared
import iOSShared

class UploadFileTracker: DatabaseModel {
    enum UploadFileTrackerError: Error {
        case notExactlyOneMimeType
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
        uploadCount: Int32) throws {

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
            uploadCount: row[Self.uploadCountField.description]
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
            Self.uploadCountField.description <- uploadCount
        )
    }
}

extension UploadFileTracker {
    // Creates an `UploadFileTracker` and copies data from the file's UploadableDataSource to a temporary file location if needed.
    // The returned `UploadFileTracker` has been inserted into the database.
    // The objectTrackerId is the id of the UploadObjectTracker for this file.
    static func create(file: UploadableFile, objectModel: DeclaredObjectModel, cloudStorageType: CloudStorageType, objectTrackerId: Int64, uploadIndex: Int32, uploadCount: Int32, config: Configuration.TemporaryFiles, hashingManager: HashingManager, db: Connection) throws -> UploadFileTracker {
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
        
        let fileTracker = try UploadFileTracker(db: db, uploadObjectTrackerId: objectTrackerId, status: .notStarted, fileUUID: file.uuid, mimeType: uploadMimeType, fileVersion: nil, localURL: url, goneReason: nil, uploadCopy: file.dataSource.isCopy, checkSum: checkSum, appMetaData: file.appMetaData, uploadIndex: uploadIndex, uploadCount: uploadCount)
        try fileTracker.insert()
        
        return fileTracker
    }
}
