
import Foundation
import ServerShared

public struct RedeemResult {
    public let accessToken: String?
    public let sharingGroupUUID: UUID
    public let userId: UserId
    public let userCreated:Bool
}
