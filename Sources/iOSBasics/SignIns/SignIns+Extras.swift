import ServerShared
import SQLite
import Foundation

extension SignIns {
    enum SignInsError: Error {
        case noSharingEntryForSharingGroupUUID
        case badCloudStorageType
        case noSignedInUser
        case nilCloudStorageType
    }

    #warning("Switch over to using this -- so I can remove the CloudStorageType from the GenericCredentials")
    
    // The sharingGroupUUID is used iff the current signed in user is a sharing user.
    func cloudStorageTypeForNewFile(db: Connection, sharingGroupUUID: UUID) throws -> CloudStorageType {
        guard let currentSignIn = signInServicesHelper.currentSignIn else {
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
            
            guard let cloudStorageType = sharingEntry.cloudStorageType else {
                throw SignInsError.nilCloudStorageType
            }

            return cloudStorageType
        }
    }
}
