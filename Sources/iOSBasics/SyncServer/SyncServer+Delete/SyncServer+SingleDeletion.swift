//
//  SyncServer+SingleDeletion.swift
//  
//
//  Created by Christopher G Prince on 2/20/21.
//

import Foundation
import SQLite
import iOSShared

extension SyncServer {
    func startSingleDeletion(tracker: UploadDeletionTracker) throws {
        guard configuration.allowUploadDownload else {
            logger.warning("allowUploadDownload is false; not doing deletion.")
            return
        }
    
        guard let trackerId = tracker.id else {
            throw SyncServerError.internalError("No tracker id")
        }
        
        guard tracker.deletionType == .fileGroupUUID else {
            throw SyncServerError.internalError("Deletion type is not file group")
        }

        let fileGroupUUID = tracker.uuid
        
        // Send the deletion request to the server.

        guard let objectEntry = try DirectoryObjectEntry.fetchSingleRow(db: db, where: DirectoryObjectEntry.fileGroupUUIDField.description == fileGroupUUID) else {
            throw SyncServerError.noObject
        }
                
        if let error = api.uploadDeletion(fileGroupUUID: fileGroupUUID, sharingGroupUUID: objectEntry.sharingGroupUUID.uuidString, trackerId: trackerId, fileTracker: tracker) {
            // As with uploads and downloads, don't make this a fatal error. We can restart this later.
            delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.userEvent(self, event: .error(error))
            }
        }
        else {
            let expiryDate = try UploadDeletionTracker.expiryDate(expiryDuration: configuration.expiryDuration)

            try tracker.update(setters: UploadDeletionTracker.statusField.description <- .deleting,
                UploadDeletionTracker.expiryField.description <- expiryDate
            )
        }
    }
}
