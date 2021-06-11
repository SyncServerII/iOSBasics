//
//  SyncServer+Conflict.swift
//  
//
//  Created by Christopher G Prince on 6/8/21.
//

import Foundation
import ServerShared
import iOSShared
import SQLite

extension SyncServer {
    // The current concept of a conflict happens due to this: https://github.com/SyncServerII/Neebla/issues/15#issuecomment-855324838
    // Basically, we tried to upload a file for a fileLabel for a file group, but someone got there first. We now need to swap in the other file uuid-- and eventually do a sync to get the file info.
    // Will currently only happen with v0 uploads.
    func handleUploadConflict(originalFileUUID: UUID, replacingFileUUID: UUID, serverFileVersion: FileVersionInt) throws {
    
        var entry: DirectoryFileEntry!
        
        guard let originalEntry = try DirectoryFileEntry.fetchSingleRow(db: db, where:
            originalFileUUID == DirectoryFileEntry.fileUUIDField.description) else {
            throw DatabaseError.noObject
        }
        
        // This is to deal with a case where a specific album sync was done and the replacement fileUUID was downloaded.
        if let replacingFileEntry = try DirectoryFileEntry.fetchSingleRow(db: db, where: originalFileUUID == DirectoryFileEntry.fileUUIDField.description) {
            entry = replacingFileEntry
        }
        else {
            entry = originalEntry
        }
        
        try entry.update(setters:
            DirectoryFileEntry.fileUUIDField.description <- replacingFileUUID,
            DirectoryFileEntry.fileVersionField.description <- serverFileVersion)

        guard let tracker = try UploadFileTracker.fetchSingleRow(db: db, where: UploadFileTracker.fileUUIDField.description == originalFileUUID) else {
            throw DatabaseError.noObject
        }
        
        try tracker.update(setters: UploadFileTracker.fileUUIDField.description <- replacingFileUUID)
    }
}
