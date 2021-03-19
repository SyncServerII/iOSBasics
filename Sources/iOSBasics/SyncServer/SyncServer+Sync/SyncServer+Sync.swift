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
    func syncHelper(completion: @escaping ()->(), sharingGroupUUID: UUID? = nil) throws {
        try triggerUploads()
        try triggerDownloads()
        try triggerDeletions()
        
        // Operates asynchronously
        getIndex(sharingGroupUUID: sharingGroupUUID) { [weak self] in
            guard let self = self else { return }
            
            self.checkOnDeferred() {
                completion()
            }
        }
    }
}
