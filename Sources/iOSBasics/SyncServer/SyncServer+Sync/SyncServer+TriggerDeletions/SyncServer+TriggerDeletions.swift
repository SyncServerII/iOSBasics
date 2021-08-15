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
    func triggerDeletions() throws {
        try triggerNotStartedDeletions()
        
        try triggerExpiredDeletions()
    }
    
    private func triggerNotStartedDeletions() throws {
        // What UploadDeletionTracker's have some files not started?
        
        let notStartedDeletions = try UploadDeletionTracker.fetch(db: db, where: UploadDeletionTracker.statusField.description == .notStarted)
        
        try startDeletions(notStartedDeletions)
    }
    
    func startDeletions(_ deletions: [UploadDeletionTracker]) throws {
        guard deletions.count > 0 else {
            return
        }
        
        for deletion in deletions {
            let uploads = try UploadObjectTracker.fetch(db: db, where: UploadObjectTracker.fileGroupUUIDField.description == deletion.uuid)
            let pendingUploads = uploads.count > 0
            
            let downloads = try DownloadObjectTracker.fetch(db: db, where: DownloadObjectTracker.fileGroupUUIDField.description == deletion.uuid)
            let pendingDownloads = downloads.count > 0
            
            guard !pendingUploads && !pendingDownloads else {
                continue
            }

            try startSingleDeletion(tracker: deletion)
        }
    }
}
