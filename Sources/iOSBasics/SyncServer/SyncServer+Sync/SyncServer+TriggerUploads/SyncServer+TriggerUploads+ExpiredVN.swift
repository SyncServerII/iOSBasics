//
//  SyncServer+TriggerUploads+ExpiredVN.swift
//  
//
//  Created by Christopher G Prince on 8/7/21.
//

import Foundation
import iOSShared
import SQLite

extension SyncServer {
    // Check with the server to see if these vN uploads have actually completed.
    func checkExpiredVNFileUploads(uploadsForSingleObject: [UploadFileTracker], object: UploadObjectTracker) {
        
        serialQueue.async {
            do {
                try self.checkExpiredVNFileUploadsAux(uploadsForSingleObject: uploadsForSingleObject, object: object)
            }
            catch let error {
                logger.error("checkExpiredVNFileUploads: \(error)")
            }
        }
    }
    
    private func checkExpiredVNFileUploadsAux(uploadsForSingleObject: [UploadFileTracker], object: UploadObjectTracker) throws {

        let id = ServerAPI.UploadsResultsId.batchUUID(object.batchUUID)
        
        api.getUploadsResults(usingId: id) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let status):
                guard let _ = status else {
                    // No deferred upload record. Should do retries.
                    do {
                        try self.retryExpiredUploads(uploadsForSingleObject: uploadsForSingleObject, object: object)
                    } catch let error {
                        logger.error("checkExpiredVNFileUploadsAux: success/retry: \(error)")
                    }
                    return
                }

                // We have a deferred uploads record for this object. Set their trackers to `uploaded`.
                do {
                    let trackers = try object.dependentFileTrackers()
                    for tracker in trackers {
                        try tracker.update(setters: UploadFileTracker.statusField.description <- .uploaded)
                    }
                } catch let error {
                    logger.error("checkExpiredVNFileUploadsAux: success: \(error)")
                    return
                }
                
                // Subsequent `sync` operations will check the status of the deferred uploads.
                
            case .failure(let error):
                logger.error("checkExpiredVNFileUploadsAux: \(error)")
            }
        }
    }
}
