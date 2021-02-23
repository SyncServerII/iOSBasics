
import Foundation
import ServerShared
 
public struct SharingGroup  {
    public struct FileGroupSummary {
        public let fileGroupUUID: UUID
        public let mostRecentDate: Date
        public let deleted: Bool
    }
        
    public let sharingGroupUUID: UUID
    public let sharingGroupName: String?
    public let deleted: Bool
    public var permission:Permission
    public let sharingGroupUsers:[SharingGroupUser]
    public let cloudStorageType: CloudStorageType?
    
    public let contentsSummary:[FileGroupSummary]?
}

public struct SharingGroupUser: Codable {
    public let name: String
}

