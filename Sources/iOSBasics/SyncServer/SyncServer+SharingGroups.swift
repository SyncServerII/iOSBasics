
import Foundation
import SQLite
import ServerShared
import iOSSignIn

extension SyncServer {
    func createSharingGroupHelper(sharingGroupUUID: UUID, sharingGroupName: String? = nil, completion: @escaping (Error?)->()) {
        let credentials:GenericCredentials
        
        do {
            let entry = try DeclaredObjectModel.fetchSingleRow(db: db, where: DeclaredObjectModel.sharingGroupUUIDField.description == sharingGroupUUID)
            
            if entry != nil {
                completion(SyncServerError.attemptToCreateExistingSharingGroup)
                return
            }
            
            credentials = try credentialsDelegate.credentialsForServerRequests(self)
        } catch let error {
            completion(error)
            return
        }
        
        api.createSharingGroup(sharingGroup: sharingGroupUUID, sharingGroupName: sharingGroupName) { [weak self] error in
            guard let self = self else { return }
            
            if error == nil {
                do {
                    let newSharingEntry = try SharingEntry(db: self.db, permission: Permission.admin, removedFromGroup: false, sharingGroupName: sharingGroupName, sharingGroupUUID: sharingGroupUUID, syncNeeded: false, cloudStorageType: credentials.cloudStorageType)
                    try newSharingEntry.insert()
                } catch let error {
                    completion(error)
                    return
                }
            }
            
            completion(error)
        }
    }
    
    func updateSharingGroup(sharingGroup: UUID, newSharingGroupName: String, completion:@escaping (Error?)->()) {
    }
}
