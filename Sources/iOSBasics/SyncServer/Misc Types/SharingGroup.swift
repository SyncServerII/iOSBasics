
import Foundation
import ServerShared

// This is modeled after ServerShared.SharingGroup.
public struct SharingGroup  {
    public struct FileGroupSummary {
        public let fileGroupUUID: UUID
        public let deleted: Bool
        
        // Indicates who should be informed of the specific change involved in this fileVersion for this file.
        public struct Inform {
            public let fileVersion: FileVersionInt
            public let fileUUID: UUID
            
            public enum WhoToInform {
                // Inform self (the user requesting this `FileGroupSummary`) about the change.
                case `self`
                
                // Don't inform self about the change
                case others
            }
            
            public let inform: WhoToInform
            
            public init(fileVersion: FileVersionInt, fileUUID: UUID, inform: WhoToInform) {
                self.fileVersion = fileVersion
                self.fileUUID = fileUUID
                self.inform = inform
            }
        }
        
        // Who should be overtly informed about these changes?
        public var inform: [Inform]?

        // MARK: Deprecated as of ServerShared.SharingGroup v0.9.2
        public let mostRecentDate: Date?
        // Max file version for all files in the file group.
        public let fileVersion: FileVersionInt?
    }
        
    public let sharingGroupUUID: UUID
    public let sharingGroupName: String?
    public let deleted: Bool
    public let permission:Permission
    public let sharingGroupUsers:[SharingGroupUser]
    public let cloudStorageType: CloudStorageType?
    public let mostRecentDate: Date?
    
    public let contentsSummary:[FileGroupSummary]?
}

public struct SharingGroupUser: Codable {
    public let name: String
}
