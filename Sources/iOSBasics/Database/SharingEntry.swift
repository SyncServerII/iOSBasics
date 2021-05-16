
// These represent an index of all sharing groups to which the user belongs.

import SQLite
import Foundation
import ServerShared
import iOSShared

class SharingEntry: DatabaseModel {
    enum SharingEntryError: Error {
        case badCloudStorageType(String)
        case badPermission(String)
    }
    
    let db: Connection
    var id: Int64!
    
    static let permissionField = Field("permission", \M.permission)
    var permission: Permission

    // If true, indicates that either the (current) user has been removed from the sharing group *or* the sharing group has been removed.
    static let deletedField = Field("deleted", \M.deleted)
    var deleted:  Bool
    
    static let sharingGroupNameField = Field("sharingGroupName", \M.sharingGroupName)
    var sharingGroupName: String?

    static let sharingGroupUUIDField = Field("sharingGroupUUID", \M.sharingGroupUUID)
    var sharingGroupUUID: UUID

    static let cloudStorageTypeField = Field("cloudStorageType", \M.cloudStorageType)
    var cloudStorageType: CloudStorageType?

    static let sharingGroupUsersDataField = Field("sharingGroupUsersData", \M.sharingGroupUsersData)
    var sharingGroupUsersData: Data
    
    func sharingGroupUsers() throws -> [SharingGroupUser] {
        return try JSONDecoder().decode([SharingGroupUser].self, from: sharingGroupUsersData)
    }
    
    init(db: Connection,
        id: Int64! = nil,
        permission: Permission,
        deleted: Bool,
        sharingGroupName: String?,
        sharingGroupUUID: UUID,
        sharingGroupUsers: [SharingGroupUser],
        cloudStorageType:CloudStorageType?) throws {
        
        self.db = db
        self.id = id
        self.sharingGroupUUID = sharingGroupUUID
        self.permission = permission
        self.deleted = deleted
        self.sharingGroupName = sharingGroupName
        self.sharingGroupUsersData = try JSONEncoder().encode(sharingGroupUsers)
        self.cloudStorageType = cloudStorageType
    }
    
    // MARK: DatabaseModel
    
    static func createTable(db: Connection) throws {
        try startCreateTable(db: db) { t in
            t.column(idField.description, primaryKey: true)
            t.column(sharingGroupUUIDField.description, unique: true)
            t.column(permissionField.description)
            t.column(deletedField.description)
            t.column(sharingGroupNameField.description)
            t.column(cloudStorageTypeField.description)
            t.column(sharingGroupUsersDataField.description)
        }
    }
    
    static func rowToModel(db: Connection, row: Row) throws -> SharingEntry {
        let data = row[Self.sharingGroupUsersDataField.description]
        let users = try JSONDecoder().decode([SharingGroupUser].self, from: data)
        
        return try SharingEntry(db: db,
            id: row[Self.idField.description],
            permission: row[Self.permissionField.description],
            deleted: row[Self.deletedField.description],
            sharingGroupName: row[Self.sharingGroupNameField.description],
            sharingGroupUUID: row[Self.sharingGroupUUIDField.description],
            sharingGroupUsers: users,
            cloudStorageType: row[Self.cloudStorageTypeField.description]
        )
    }
    
    func insert() throws {
        try doInsertRow(db: db, values:
            Self.permissionField.description <- permission,
            Self.deletedField.description <- deleted,
            Self.sharingGroupNameField.description <- sharingGroupName,
            Self.sharingGroupUUIDField.description <- sharingGroupUUID,
            Self.sharingGroupUsersDataField.description <- sharingGroupUsersData,
            Self.cloudStorageTypeField.description <- cloudStorageType
        )
    }
}

extension SharingEntry {
    // Update or insert the SharingEntry corresponding to the passed sharingGroup.
    static func upsert(sharingGroup: ServerShared.SharingGroup, db: Connection) throws {
        guard let sharingGroupUUID = try UUID.from(sharingGroup.sharingGroupUUID) else {
            throw DatabaseError.invalidUUID
        }

        if let sharingEntry = try SharingEntry.fetchSingleRow(db: db, where: SharingEntry.sharingGroupUUIDField.description == sharingGroupUUID) {

            if sharingGroup.sharingGroupName != sharingEntry.sharingGroupName {
                try sharingEntry.update(setters: SharingEntry.sharingGroupNameField.description
                        <- sharingGroup.sharingGroupName
                )
            }
            
            // Handling both delete and undelete case because if a user is removed and then re-added to a sharing group, we'll have an "undelete".
            if sharingGroup.deleted != sharingEntry.deleted {
                try sharingEntry.update(setters:
                    SharingEntry.deletedField.description
                        <- sharingGroup.deleted ?? false
                )
            }
        }
        else {            
            guard let permission = sharingGroup.permission else {
                throw SyncServerError.internalError("Could not get permission")
            }
            
            var cloudStorageType: CloudStorageType?
            
            if let cloudStorageTypeString = sharingGroup.cloudStorageType {
                guard let type = CloudStorageType(rawValue: cloudStorageTypeString) else {
                    throw SyncServerError.internalError("Could not get cloud storage type")
                }
                
                cloudStorageType = type
            }
            
            guard let sharingGroupUsers = sharingGroup.sharingGroupUsers else {
                throw SyncServerError.internalError("Could not get sharing group users")
            }
            
            let users = try sharingGroupUsers.map { user -> iOSBasics.SharingGroupUser in
                guard let name = user.name else {
                    throw SyncServerError.internalError("Could not get sharing group user name")
                }
                
                return iOSBasics.SharingGroupUser(name: name)
            }
            
            let deleted = sharingGroup.deleted ?? false
            
            logger.info("Creating new SharingEntry: \(sharingGroupUUID); name: \(String(describing: sharingGroup.sharingGroupName))")
            
            let newSharingEntry = try SharingEntry(db: db, permission: permission, deleted: deleted, sharingGroupName: sharingGroup.sharingGroupName, sharingGroupUUID: sharingGroupUUID, sharingGroupUsers: users, cloudStorageType: cloudStorageType)
            try newSharingEntry.insert()
        }
    }
    
    static func getGroups(db: Connection) throws -> [iOSBasics.SharingGroup] {
        let entries = try SharingEntry.fetch(db: db)

        return try entries.map { entry -> iOSBasics.SharingGroup in
            let sharingGroup = iOSBasics.SharingGroup(sharingGroupUUID: entry.sharingGroupUUID, sharingGroupName: entry.sharingGroupName, deleted: entry.deleted, permission: entry.permission, sharingGroupUsers: try entry.sharingGroupUsers(), cloudStorageType: entry.cloudStorageType, contentsSummary: nil)
             return sharingGroup
        }
    }
}
