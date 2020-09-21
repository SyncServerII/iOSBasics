
import Foundation
import ServerShared

public struct SharingGroup  {
    public let sharingGroupUUID: UUID
    public let sharingGroupName: String?
    public let deleted: Bool
    public var permission:Permission
    public let sharingGroupUsers:[SharingGroupUser]
    public let cloudStorageType: CloudStorageType?
}

public struct SharingGroupUser: Codable {
    public let name: String
}

