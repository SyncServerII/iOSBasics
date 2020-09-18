
import Foundation
import SQLite
import iOSShared

extension SyncServer {
    func queueHelper<DECL: DeclarableObject, DWL: DownloadableFile>(downloads: Set<DWL>, declaration: DECL) throws {
        guard downloads.count > 0 else {
            throw SyncServerError.noUploads
        }
        
        guard declaration.declaredFiles.count > 0 else {
            throw SyncServerError.noDeclaredFiles
        }
        
        // Make sure all files in the downloads and declarations have distinct uuid's
        guard DWL.hasDistinctUUIDs(in: downloads) else {
            throw SyncServerError.downloadsDoNotHaveDistinctUUIDs
        }
        
        guard DECL.DeclaredFile.hasDistinctUUIDs(in: declaration.declaredFiles) else {
            throw SyncServerError.declaredFilesDoNotHaveDistinctUUIDs
        }
            
        // Make sure all files in the downloads are in the declaration.
        for download in downloads {
            let declaredFiles = declaration.declaredFiles.filter {$0.uuid == download.uuid}
            guard declaredFiles.count == 1 else {
                throw SyncServerError.fileNotDeclared
            }
        }
        
        // Make sure this DeclaredObject has been registered.
        guard let declaredObject = try DeclaredObjectModel.fetchSingleRow(db: db,
            where: declaration.fileGroupUUID == DeclaredObjectModel.fileGroupUUIDField.description) else {
            throw SyncServerError.noObject
        }
        
        // And that it matches the one we have stored.
        try declaredObjectCanBeQueued(declaration: declaration, declaredObject:declaredObject)
                
        // If there is an active download for this fileGroupUUID, then this download will be locally queued for later processing. If there is not one, we'll trigger the download now.
        let activeDownloadsForThisFileGroup = try DownloadObjectTracker.anyDownloadsWith(status: .downloading, fileGroupUUID: declaration.fileGroupUUID, db: db)
                
        // Create a DownloadObjectTracker and DownloadFileTracker(s)
        let downloadsArray = Array(downloads)
        let (newObjectTrackerId, _, fileTrackers) = try createNewTrackers(fileGroupUUID: declaration.fileGroupUUID, declaration: declaration, downloads: downloadsArray)

        guard !activeDownloadsForThisFileGroup else {
            // There are active downloads for this file group.
            delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.downloadQueue(self, event: .queued(fileGroupUUID: declaration.fileGroupUUID))
            }
            return
        }
        
        // Can trigger these downloads.
        for (download, tracker) in zip(downloadsArray, fileTrackers) {
            let file = FileObject(fileUUID: download.uuid.uuidString, fileVersion: download.fileVersion, trackerId: newObjectTrackerId)
            
            if let error = api.downloadFile(file: file, sharingGroupUUID: declaration.sharingGroupUUID.uuidString) {
                // Going to keep going here despite the error because (a) we might have started downloads, and (b) we can restart these as part of our normal error/restart process.
                logger.error("\(error)")
            }
            else {
                try tracker.update(setters: DownloadFileTracker.statusField.description <- .downloading)
            }
        }
    }
    
    // Add a new tracker into DownloadObjectTracker, and one for each new download.
    // The order and length of the elements returned in the [DownloadFileTracker] array is the same as in the downloads array.
    private func createNewTrackers<DECL: DeclarableObject, DWL: DownloadableFile>(fileGroupUUID: UUID, declaration: DECL, downloads: [DWL]) throws -> (newObjectTrackerId: Int64, DownloadObjectTracker, [DownloadFileTracker]) {
    
        let newObjectTracker = try DownloadObjectTracker(db: db, fileGroupUUID: fileGroupUUID)
        try newObjectTracker.insert()
        
        guard let newObjectTrackerId = newObjectTracker.id else {
            throw SyncServerError.internalError("No object tracker id")
        }
        
        logger.debug("newObjectTrackerId: \(newObjectTrackerId)")
        
        var trackers = [DownloadFileTracker]()
        
        // Create a new `DownloadFileTracker` for each file we're downloading.
        for file in downloads {
            let fileTracker = try DownloadFileTracker(db: db, downloadObjectTrackerId: newObjectTrackerId, status: .notStarted, fileUUID: file.uuid, fileVersion: file.fileVersion, localURL: nil)
            try fileTracker.insert()
            logger.debug("newFileTracker: \(String(describing: fileTracker.id))")
            
            trackers += [fileTracker]
        }
        
        return (newObjectTrackerId, newObjectTracker, trackers)
    }
}
