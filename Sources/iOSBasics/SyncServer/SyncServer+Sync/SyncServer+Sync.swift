//
//  SyncServer+Sync.swift
//  
//
//  Created by Christopher G Prince on 9/6/20.
//

import Foundation
import SQLite
import iOSShared

extension SyncServer {
    func syncHelper(sharingGroupUUID: UUID? = nil) throws {
        guard api.networking.reachability.isReachable else {
            logger.info("Could not sync: Network not reachable")
            throw SyncServerError.networkNotReachable
        }
        
        getIndex(sharingGroupUUID: sharingGroupUUID)
        
        try triggerUploads()
        try triggerDownloads()
        try triggerDeletions()

        checkOnDeferred()
    }
}
