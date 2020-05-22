
// These represent an index of all sharing groups to which the user belongs.

import SQLite
import Foundation
import ServerShared

class SharingEntry: DatabaseModel {
    enum SharingEntryError: Error {
        case badCloudStorageType(String)
        case badPermission(String)
    }
    
    let db: Connection
    var id: Int64!

    static let masterVersionField = Field("masterVersion", \M.masterVersion)
    var masterVersion: Int64
    
    static let permissionField = Field("permission", \M.permission)
    var permission: String?

    static let removedFromGroupField = Field("removedFromGroup", \M.removedFromGroup)
    var removedFromGroup:  Bool
    
    static let sharingGroupNameField = Field("sharingGroupName", \M.sharingGroupName)
    var sharingGroupName: String?

    static let sharingGroupUUIDField = Field("sharingGroupUUID", \M.sharingGroupUUID)
    var sharingGroupUUID: String

    static let syncNeededField = Field("syncNeeded", \M.syncNeeded)
    var syncNeeded: Bool

    static let cloudStorageTypeField = Field("cloudStorageType", \M.cloudStorageType)
    var cloudStorageType: String?
    
    init(db: Connection, masterVersion: Int64, permission: String? = nil, removedFromGroup: Bool, sharingGroupName: String?, sharingGroupUUID: String, syncNeeded: Bool, cloudStorageType: String? = nil) throws {

        if let cloudStorageType = cloudStorageType {
            guard let _ = CloudStorageType(rawValue: cloudStorageType) else {
                throw SharingEntryError.badCloudStorageType(cloudStorageType)
            }
        }

        if let permission = permission {
            guard let _ = Permission(rawValue: permission) else {
                throw SharingEntryError.badPermission(permission)
            }
        }
        
        self.db = db
        self.sharingGroupUUID = sharingGroupUUID
        self.masterVersion = masterVersion
        self.permission = permission
        self.removedFromGroup = removedFromGroup
        self.sharingGroupName = sharingGroupName
        self.syncNeeded = syncNeeded
        self.cloudStorageType = cloudStorageType
    }
    
    // MARK: DatabaseModel
    
    static func createTable(db: Connection) throws {
        try startCreateTable(db: db) { t in
            t.column(sharingGroupUUIDField.description, primaryKey: true)
            t.column(masterVersionField.description)
            t.column(permissionField.description)
            t.column(removedFromGroupField.description)
            t.column(sharingGroupNameField.description)
            t.column(syncNeededField.description)
            t.column(cloudStorageTypeField.description)
        }
    }
    
    static func rowToModel(db: Connection, row: Row) throws -> SharingEntry {
        return try SharingEntry(db: db,
            masterVersion: row[Self.masterVersionField.description],
            permission: row[Self.permissionField.description],
            removedFromGroup: row[Self.removedFromGroupField.description],
            sharingGroupName: row[Self.sharingGroupNameField.description],
            sharingGroupUUID: row[Self.sharingGroupUUIDField.description],
            syncNeeded: row[Self.syncNeededField.description],
            cloudStorageType: row[Self.cloudStorageTypeField.description]
        )
    }
    
    func insert() throws {
        try doInsertRow(db: db, values:
            Self.masterVersionField.description <- masterVersion,
            Self.permissionField.description <- permission,
            Self.removedFromGroupField.description <- removedFromGroup,
            Self.sharingGroupNameField.description <- sharingGroupName,
            Self.sharingGroupUUIDField.description <- sharingGroupUUID,
            Self.syncNeededField.description <- syncNeeded,
            Self.cloudStorageTypeField.description <- cloudStorageType
        )
    }
}


