//
//  SyncServer+TriggerDeletions.swift
//  
//
//  Created by Christopher G Prince on 2/20/21.
//

import Foundation
import SQLite
import iOSShared

extension SyncServer {
    // Re-check of queued deletions.
    func triggerDeletions() throws {
        // What UploadDeletionTracker's have some files not started?
        
        let notStartedDeletions = try UploadDeletionTracker.fetch(db: db, where: UploadDeletionTracker.statusField.description == .notStarted)
        
        guard notStartedDeletions.count > 0 else {
            return
        }
        
        logger.debug("Starting \(notStartedDeletions.count) object deletion(s).")
        
        for deletion in notStartedDeletions {
            try startSingleDeletion(tracker: deletion)
        }
    }
}
