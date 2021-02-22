//
//  SyncServer+SyncResults.swift
//  
//
//  Created by Christopher G Prince on 2/21/21.
//

import Foundation

extension SyncServer {
    // When no sharing group was passed to the server.
    func getNoIndexResult(indexResult: ServerAPI.IndexResult) throws -> [SyncResult.SharingGroup] {
        return try indexResult.sharingGroups.map { sharingGroup -> SyncResult.SharingGroup in
            let deleted = sharingGroup.deleted ?? false
            var summaries = [SyncResult.SharingGroup.FileGroupSummary]()
        
            if let fileGroupSummary = sharingGroup.contentsSummary {
                let contentsSummary = try fileGroupSummary.map { summary -> SyncResult.SharingGroup.FileGroupSummary in
                    guard let fileGroupUUID = try UUID.from(summary.fileGroupUUID) else {
                        throw SyncServerError.internalError("Could not get fileGroupUUID")
                    }
                    
                    guard let mostRecentDate = summary.mostRecentDate else {
                        throw SyncServerError.internalError("Could not get mostRecentDate")
                    }
            
                    return SyncResult.SharingGroup.FileGroupSummary(fileGroupUUID: fileGroupUUID, mostRecentDate: mostRecentDate, deleted: summary.deleted ?? false)
                }
                
                summaries = contentsSummary
            }

            guard let sharingGroupUUID = try UUID.from(sharingGroup.sharingGroupUUID) else {
                throw SyncServerError.internalError("Could not get sharingGroupUUID")
            }
                    
            return SyncResult.SharingGroup(sharingGroupUUID: sharingGroupUUID, deleted: deleted, contentsSummary: summaries)
        }
    }
}
