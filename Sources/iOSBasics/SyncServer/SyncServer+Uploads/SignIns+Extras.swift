import ServerShared
import SQLite
import Foundation

extension SyncServer {    
    // The sharingGroupUUID is used iff the current signed in user is a sharing user.
    // The user must do at least one `sync` call prior to queuing an upload or this throws an error.
    func cloudStorageTypeForNewFile(sharingGroupUUID: UUID) throws -> CloudStorageType {
        if let cloudStorageType = signIns.signInServicesHelper.cloudStorageType {
            return cloudStorageType
        }
        else {
            let sharingGroups = try self.sharingGroups().filter
                { $0.sharingGroupUUID == sharingGroupUUID}
            if sharingGroups.count == 0 {
                throw SyncServerError.unknownSharingGroup
            }
            
            if sharingGroups.count > 1 {
                throw SyncServerError.internalError("More than one one sharing group found!")
            }
            
            let sharingGroup = sharingGroups[0]

            guard let cloudStorageType = sharingGroup.cloudStorageType else {
                throw SyncServerError.noCloudStorageType
            }
            
            return cloudStorageType
        }
    }
}
