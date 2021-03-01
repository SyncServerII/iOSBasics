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
        getIndex(sharingGroupUUID: sharingGroupUUID)
        
        try triggerUploads()
        try triggerDownloads()
        try triggerDeletions()
        
        checkOnDeferred()
    }
}
