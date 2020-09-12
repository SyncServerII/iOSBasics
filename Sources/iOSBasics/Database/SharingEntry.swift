
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
    
    static let permissionField = Field("permission", \M.permission)
    var permission: String?

    static let removedFromGroupField = Field("removedFromGroup", \M.removedFromGroup)
    var removedFromGroup:  Bool
    
    static let sharingGroupNameField = Field("sharingGroupName", \M.sharingGroupName)
    var sharingGroupName: String?

    static let sharingGroupUUIDField = Field("sharingGroupUUID", \M.sharingGroupUUID)
    var sharingGroupUUID: UUID

    static let syncNeededField = Field("syncNeeded", \M.syncNeeded)
    var syncNeeded: Bool

    static let cloudStorageTypeField = Field("cloudStorageType", \M.cloudStorageType)
    var cloudStorageType: String?
    
    init(db: Connection,
        id: Int64! = nil,
        permission: String? = nil,
        removedFromGroup: Bool,
        sharingGroupName: String?,
        sharingGroupUUID: UUID,
        syncNeeded: Bool,
        cloudStorageType:
        String? = nil) throws {

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
        self.id = id
        self.sharingGroupUUID = sharingGroupUUID
        self.permission = permission
        self.removedFromGroup = removedFromGroup
        self.sharingGroupName = sharingGroupName
        self.syncNeeded = syncNeeded
        self.cloudStorageType = cloudStorageType
    }
    
    // MARK: DatabaseModel
    
    static func createTable(db: Connection) throws {
        try startCreateTable(db: db) { t in
            t.column(idField.description, primaryKey: true)
            t.column(sharingGroupUUIDField.description, unique: true)
            t.column(permissionField.description)
            t.column(removedFromGroupField.description)
            t.column(sharingGroupNameField.description)
            t.column(syncNeededField.description)
            t.column(cloudStorageTypeField.description)
        }
    }
    
    static func rowToModel(db: Connection, row: Row) throws -> SharingEntry {
        return try SharingEntry(db: db,
            id: row[Self.idField.description],
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
            Self.permissionField.description <- permission,
            Self.removedFromGroupField.description <- removedFromGroup,
            Self.sharingGroupNameField.description <- sharingGroupName,
            Self.sharingGroupUUIDField.description <- sharingGroupUUID,
            Self.syncNeededField.description <- syncNeeded,
            Self.cloudStorageTypeField.description <- cloudStorageType
        )
    }
}

extension SharingEntry {
    // Update or insert the SharingEntry corresponding to the passed sharingGroup.
    static func upsert(sharingGroup: ServerShared.SharingGroup, db: Connection) throws {
        guard let sharingGroupUUIDString = sharingGroup.sharingGroupUUID,
              let sharingGroupUUID = UUID(uuidString: sharingGroupUUIDString) else {
            throw DatabaseModelError.invalidUUID
        }

        if let sharingEntry = try SharingEntry.fetchSingleRow(db: db, where: SharingEntry.sharingGroupUUIDField.description == sharingGroupUUID) {
            if sharingGroup.sharingGroupName != sharingEntry.sharingGroupName {
                try sharingEntry.update(setters: SharingEntry.sharingGroupNameField.description <- sharingGroup.sharingGroupName)
            }
        }
        else {
            // `removedFromGroup` set to false because we shouldn't be getting this call unless the current user is part of the sharing group.
            // Should eventually detect when a user is removed from a sharing group and update this.
            let newSharingEntry = try SharingEntry(db: db, permission: sharingGroup.permission?.rawValue, removedFromGroup: false, sharingGroupName: sharingGroup.sharingGroupName, sharingGroupUUID: sharingGroupUUID, syncNeeded: false, cloudStorageType: sharingGroup.cloudStorageType)
            try newSharingEntry.insert()
        }
    }
}
