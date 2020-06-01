import ServerShared
import SQLite
import Foundation

extension SignIns {
    enum SignInsError: Error {
        case noSharingEntryForSharingGroupUUID
        case badCloudStorageType
        case noSignedInUser
    }

    // The sharingGroupUUID is used iff the current signed in user is a sharing user.
    func cloudStorageTypeForNewFile(db: Connection, sharingGroupUUID: UUID) throws -> CloudStorageType {
        guard let currentSignIn = signInServices.manager.currentSignIn else {
            throw SignInsError.noSignedInUser
        }
        
        if let cloudStorageType = currentSignIn.cloudStorageType {
            return cloudStorageType
        }
        else {
            guard let sharingEntry = try SharingEntry.fetchSingleRow(db: db, where:
                sharingGroupUUID == SharingEntry.sharingGroupUUIDField.description) else {
                throw SignInsError.noSharingEntryForSharingGroupUUID
            }
            
            guard let typeString = sharingEntry.cloudStorageType,
                let cloudStorageType = CloudStorageType(rawValue: typeString) else {
                throw SignInsError.badCloudStorageType
            }
            
            return cloudStorageType
        }
    }
}
