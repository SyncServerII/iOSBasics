
import Foundation
import ServerShared

extension SyncServer {
    func getSharingGroupsHelper() throws -> [iOSBasics.SharingGroup]  {
        let sharingGroups = try SharingEntry.getGroups(db: db)        
        return sharingGroups.filter { !$0.deleted }
    }
}
