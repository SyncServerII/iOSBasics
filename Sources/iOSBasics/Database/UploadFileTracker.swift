// Represents a file to be or being uploaded.

import SQLite
import Foundation
import ServerShared

class UploadFileTracker: DatabaseModel {
    let db: Connection
    var id: Int64!
    
    enum Status : String {
        case notStarted
        case uploading
        
        // This is for both successfully uploaded files and files that cannot be uploaded due to a gone response.
        case uploaded
    }
    
    static let statusField = Field("status", \M.status)
    var status: Status

    static let sharingGroupUUIDField = Field("sharingGroupUUID", \M.sharingGroupUUID)
    var sharingGroupUUID: UUID
    
    static let appMetaDataField = Field("appMetaData", \M.appMetaData)
    var appMetaData: String?

    static let appMetaDataVersionField = Field("appMetaDataVersion", \M.appMetaDataVersion)
    var appMetaDataVersion: AppMetaDataVersionInt?

    static let fileGroupUUIDField = Field("fileGroupUUID", \M.fileGroupUUID)
    var fileGroupUUID: UUID

    static let fileUUIDField = Field("fileUUID", \M.fileUUID)
    var fileUUID: UUID
    
    static let fileVersionField = Field("fileVersion", \M.fileVersion)
    var fileVersion: FileVersionInt?

    static let localURLField = Field("localURL", \M.localURL)
    var localURL:URL?
    
    static let mimeTypeField = Field("mimeType", \M.mimeType)
    var mimeType: MimeType?
    
    static let goneReasonField = Field("goneReason", \M.goneReason)
    var goneReason: GoneReason?

    static let uploadCopyField = Field("uploadCopy", \M.uploadCopy)
    var uploadCopy: Bool

    static let uploadUndeletionField = Field("uploadUndeletion", \M.uploadUndeletion)
    var uploadUndeletion: Bool
    
    static let checkSumField = Field("checkSum", \M.checkSum)
    var checkSum: String?
    
    init(db: Connection,
        id: Int64! = nil,
        status: Status,
        sharingGroupUUID: UUID,
        appMetaData: String?,
        appMetaDataVersion: AppMetaDataVersionInt?,
        fileGroupUUID: UUID,
        fileUUID: UUID,
        fileVersion: FileVersionInt?,
        localURL:URL?,
        mimeType: MimeType?,
        goneReason: GoneReason?,
        uploadCopy: Bool,
        uploadUndeletion: Bool,
        checkSum: String?) throws {

        self.db = db
        self.id = id
        self.status = status
        self.sharingGroupUUID = sharingGroupUUID
        self.appMetaData = appMetaData
        self.appMetaDataVersion = appMetaDataVersion
        self.fileGroupUUID = fileGroupUUID
        self.fileUUID = fileUUID
        self.fileVersion = fileVersion
        self.localURL = localURL
        self.mimeType = mimeType
        self.goneReason = goneReason
        self.uploadCopy = uploadCopy
        self.uploadUndeletion = uploadUndeletion
        self.checkSum = checkSum
    }
    
    // MARK: DatabaseModel
    
    static func createTable(db: Connection) throws {
        try startCreateTable(db: db) { t in
            t.column(idField.description, primaryKey: true)
            t.column(statusField.description)
            t.column(sharingGroupUUIDField.description)
            t.column(appMetaDataField.description)
            t.column(appMetaDataVersionField.description)
            t.column(fileGroupUUIDField.description)
            t.column(fileUUIDField.description)
            t.column(fileVersionField.description)
            t.column(localURLField.description)
            t.column(mimeTypeField.description)
            t.column(goneReasonField.description)
            t.column(uploadCopyField.description)
            t.column(uploadUndeletionField.description)
            t.column(checkSumField.description)
        }
    }
    
    static func rowToModel(db: Connection, row: Row) throws -> UploadFileTracker {
        return try UploadFileTracker(db: db,
            id: row[Self.idField.description],
            status: row[Self.statusField.description],
            sharingGroupUUID: row[Self.sharingGroupUUIDField.description],
            appMetaData: row[Self.appMetaDataField.description],
            appMetaDataVersion: row[Self.appMetaDataVersionField.description],
            fileGroupUUID: row[Self.fileGroupUUIDField.description],
            fileUUID: row[Self.fileUUIDField.description],
            fileVersion: row[Self.fileVersionField.description],
            localURL: row[Self.localURLField.description],
            mimeType: row[Self.mimeTypeField.description],
            goneReason: row[Self.goneReasonField.description],
            uploadCopy: row[Self.uploadCopyField.description],
            uploadUndeletion: row[Self.uploadUndeletionField.description],
            checkSum: row[Self.checkSumField.description]
        )
    }
    
    func insert() throws {
        try doInsertRow(db: db, values:
            Self.statusField.description <- status,
            Self.sharingGroupUUIDField.description <- sharingGroupUUID,
            Self.appMetaDataField.description <- appMetaData,
            Self.appMetaDataVersionField.description <- appMetaDataVersion,
            Self.fileGroupUUIDField.description <- fileGroupUUID,
            Self.fileUUIDField.description <- fileUUID,
            Self.fileVersionField.description <- fileVersion,
            Self.localURLField.description <- localURL,
            Self.mimeTypeField.description <- mimeType,
            Self.goneReasonField.description <- goneReason,
            Self.uploadCopyField.description <- uploadCopy,
            Self.uploadUndeletionField.description <- uploadUndeletion,
            Self.checkSumField.description <- checkSum
        )
    }
}
