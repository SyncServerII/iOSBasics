//
//  SyncServer+TriggerDownloads+Expiry.swift
//  
//
//  Created by Christopher G Prince on 8/15/21.
//

import Foundation
import SQLite

extension SyncServer {
    // Doesn't actually restart downloads. Just resets.
    func resetExpiredDownloads() throws {
        let expiredDownloadTrackers = try DownloadFileTracker.fetch(db: db, where: DownloadFileTracker.statusField.description == .downloading).filter {
            try $0.hasExpired()
        }
        
        for expiredDownloadTracker in expiredDownloadTrackers {
            try expiredDownloadTracker.reset()
        }
    }
}
