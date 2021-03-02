//
//  SyncServer+SyncResults.swift
//  
//
//  Created by Christopher G Prince on 2/21/21.
//

import Foundation
import ServerShared

extension SyncServer {
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
                    
                    guard let mostRecentDate = summary.mostRecentDate else {
                        throw SyncServerError.internalError("Could not get mostRecentDate")
                    }

                    guard let fileVersion = summary.fileVersion else {
                        throw SyncServerError.internalError("Could not get fileVersion")
                    }
                    
                    return iOSBasics.SharingGroup.FileGroupSummary(fileGroupUUID: fileGroupUUID, mostRecentDate: mostRecentDate, deleted: summary.deleted ?? false, fileVersion: fileVersion)
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
            
            return iOSBasics.SharingGroup(sharingGroupUUID: sharingGroupUUID, sharingGroupName: sharingGroup.sharingGroupName, deleted: deleted, permission: permission, sharingGroupUsers: sharingGroupUsers, cloudStorageType: cloudStorageType, contentsSummary: summaries)
        }
    }
}
