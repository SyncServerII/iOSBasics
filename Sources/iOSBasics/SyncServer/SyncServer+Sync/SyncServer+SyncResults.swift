//
//  SyncServer+SyncResults.swift
//  
//
//  Created by Christopher G Prince on 2/21/21.
//

import Foundation
import ServerShared
import iOSShared

extension SyncServer {
    typealias iOSBasicsInform = iOSBasics.SharingGroup.FileGroupSummary.Inform
    
    // When no sharing group was passed to the server.
    func getNoIndexResult(indexResult: ServerAPI.IndexResult) throws -> [iOSBasics.SharingGroup] {
        return try indexResult.sharingGroups.map { sharingGroup -> iOSBasics.SharingGroup in
            let deleted = sharingGroup.deleted ?? false
            var summaries = [iOSBasics.SharingGroup.FileGroupSummary]()
        
            if let fileGroupSummary = sharingGroup.contentsSummary {
                let contentsSummary = try fileGroupSummary.map { summary -> iOSBasics.SharingGroup.FileGroupSummary in
                    guard let fileGroupUUID = try UUID.from(summary.fileGroupUUID) else {
                        throw SyncServerError.internalError("Could not get fileGroupUUID")
                    }
                    
                    var result:[iOSBasicsInform]! = [iOSBasicsInform]()
                    
                    if let inform = summary.inform, inform.count > 0 {
                        result = try inform.compactMap { (item) -> (iOSBasicsInform?) in
                            guard let fileUUID = try UUID.from(item.fileUUID) else {
                                logger.error("Failed converting item.fileUUID: \(item.fileUUID)")
                                return nil
                            }

                            let who:iOSBasicsInform.WhoToInform = item.inform == .self ? .self : .others
                            return iOSBasicsInform(fileVersion: item.fileVersion, fileUUID: fileUUID, inform: who)
                        }
                    }
                    
                    if result == nil || result?.count == 0 {
                        result = nil
                    }
                    
                    return iOSBasics.SharingGroup.FileGroupSummary(fileGroupUUID: fileGroupUUID, deleted: summary.deleted ?? false, inform: result, mostRecentDate: nil, fileVersion: nil)
                }
                
                summaries = contentsSummary
            }

            guard let sharingGroupUUID = try UUID.from(sharingGroup.sharingGroupUUID) else {
                throw SyncServerError.internalError("Could not get sharingGroupUUID")
            }
            
            guard let permission = sharingGroup.permission else {
                throw SyncServerError.internalError("Could not get Permission")
            }
            
            let sharingGroupUsers = try (sharingGroup.sharingGroupUsers ?? []).map { user -> iOSBasics.SharingGroupUser in
                guard let userName = user.name else {
                    throw SyncServerError.internalError("Could not get sharingGroupUUID")
                }
                return iOSBasics.SharingGroupUser(name: userName)
            }
            
            var cloudStorageType: CloudStorageType?
            if let type = sharingGroup.cloudStorageType {
                cloudStorageType = CloudStorageType(rawValue: type)
            }
            
            return iOSBasics.SharingGroup(sharingGroupUUID: sharingGroupUUID, sharingGroupName: sharingGroup.sharingGroupName, deleted: deleted, permission: permission, sharingGroupUsers: sharingGroupUsers, cloudStorageType: cloudStorageType, mostRecentDate: sharingGroup.mostRecentDate, contentsSummary: summaries.count == 0 ? nil : summaries)
        }
    }
}
