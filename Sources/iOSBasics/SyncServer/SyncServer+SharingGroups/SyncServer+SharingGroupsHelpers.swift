
import Foundation
import ServerShared

extension SyncServer {
    func getSharingGroupsHelper() throws -> [iOSBasics.SharingGroup]  {
        return try SharingEntry.getGroups(db: db)
    }
}
