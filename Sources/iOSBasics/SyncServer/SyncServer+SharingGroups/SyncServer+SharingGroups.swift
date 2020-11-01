
import Foundation
import SQLite
import ServerShared
import iOSSignIn

extension SyncServer {
/*
    func createSharingGroupHelper(sharingGroupUUID: UUID, sharingGroupName: String? = nil, completion: @escaping (Error?)->()) {
        do {
            guard try SharingEntry.numberRows(db: db) > 0 else {
                completion(SyncServerError.sharingGroupsNotFound)
                return
            }
        } catch let error {
            completion(error)
            return
        }
        
        do {
            let entry = try SharingEntry.fetchSingleRow(db: db, where: SharingEntry.sharingGroupUUIDField.description == sharingGroupUUID)
            guard entry == nil else {
                completion(SyncServerError.attemptToCreateExistingSharingGroup)
                return
            }
        } catch let error {
            completion(error)
            return
        }
        
        api.createSharingGroup(sharingGroup: sharingGroupUUID, sharingGroupName: sharingGroupName) { [weak self] error in
            guard let self = self else { return }
            
            if error == nil {
                // Could directly create a `SharingEntry` here, without a network request, but this is simpler.
                self.getIndex(sharingGroupUUID: nil)
            }
            
            completion(error)
        }
    }
    
    func updateSharingGroupHelper(sharingGroupUUID: UUID, newSharingGroupName: String, completion:@escaping (Error?)->()) {
        
        do {
            guard let _ = try SharingEntry.fetchSingleRow(db: db, where: SharingEntry.sharingGroupUUIDField.description == sharingGroupUUID) else {
                completion(SyncServerError.sharingGroupNotFound)
                return
            }
        } catch let error {
            completion(error)
            return
        }
        
        api.updateSharingGroup(sharingGroup: sharingGroupUUID, newSharingGroupName: newSharingGroupName) { [weak self] error in
            guard let self = self else { return }
            
            if error == nil {
                self.getIndex(sharingGroupUUID: nil)
            }
            
            completion(error)
        }
    }
    
    func removeFromSharingGroupHelper(sharingGroupUUID: UUID, completion:@escaping (Error?)->()) {
    
        do {
            guard let _ = try SharingEntry.fetchSingleRow(db: db, where: SharingEntry.sharingGroupUUIDField.description == sharingGroupUUID) else {
                completion(SyncServerError.sharingGroupNotFound)
                return
            }
        } catch let error {
            completion(error)
            return
        }

        api.removeFromSharingGroup(sharingGroup: sharingGroupUUID) { error in
            if error == nil {
                self.getIndex(sharingGroupUUID: nil)
            }
            
            completion(error)
        }
    }
    */
}
