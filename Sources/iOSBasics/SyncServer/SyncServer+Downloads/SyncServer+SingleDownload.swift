//
//  File.swift
//  
//
//  Created by Christopher G Prince on 9/18/20.
//

import Foundation
import iOSShared
import SQLite
import ServerShared

extension SyncServer {
    func singleDownload(fileUUID: UUID, fileVersion: FileVersionInt, tracker: DownloadFileTracker, objectTrackerId: Int64, sharingGroupUUID: UUID) throws {
        let file = FileObject(fileUUID: fileUUID.uuidString, fileVersion: fileVersion, trackerId: objectTrackerId)
        
        if let error = api.downloadFile(file: file, sharingGroupUUID: sharingGroupUUID.uuidString) {
            // Going to keep going here despite the error because (a) we might have started downloads, and (b) we can restart these as part of our normal error/restart process.
            delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.error(self, error: error)
            }
        }
        else {
            try tracker.update(setters: DownloadFileTracker.statusField.description <- .downloading)
        }
    }
}
