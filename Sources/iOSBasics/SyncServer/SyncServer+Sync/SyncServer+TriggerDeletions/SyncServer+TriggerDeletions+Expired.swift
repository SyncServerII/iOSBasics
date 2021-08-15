//
//  SyncServer+TriggerDeletions+Expired.swift
//  
//
//  Created by Christopher G Prince on 8/14/21.
//

import Foundation
import SQLite
import iOSShared

extension SyncServer {
    func triggerExpiredDeletions() throws {
        let expiredDeletionTrackers = try UploadDeletionTracker.fetch(db: db, where: UploadDeletionTracker.statusField.description == .deleting).filter {
            try $0.hasExpired()
        }
        
        try startDeletions(expiredDeletionTrackers)
    }
}
