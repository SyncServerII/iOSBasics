
import Foundation
import ServerShared

extension SyncServer {
    func getSharingGroupsHelper() throws -> [iOSBasics.SharingGroup]  {
        let sharingGroups = try SharingEntry.getGroups(db: db)
        guard sharingGroups.count > 0 else {
            throw SyncServerError.sharingGroupsNotFound
        }
        
        return sharingGroups.filter { !$0.deleted }
    }
}
