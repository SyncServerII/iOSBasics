//
//  SyncServer+RestartDownloads.swift
//  
//
//  Created by Christopher G Prince on 6/20/21.
//

import Foundation

extension SyncServer {
    func restartDownloadHelper(fileGroupUUID: UUID) throws {
        try DownloadObjectTracker.reset(fileGroupUUID: fileGroupUUID, db: db)
    }
}
