
import Foundation
import SQLite
import iOSShared

extension SyncServer {
    func queueHelper<DWL: ObjectShouldBeDownloaded>(download: DWL) throws {
        guard download.downloads.count > 0 else {
            throw SyncServerError.noDownloads
        }
        
        let fileUUIDsToDownload = download.downloads.map {$0.uuid}
        
        // Make sure all files in the downloads have distinct uuid's
        guard fileUUIDsToDownload.count == Set<UUID>(fileUUIDsToDownload).count else {
            throw SyncServerError.downloadsDoNotHaveDistinctUUIDs
        }
        
        guard let objectEntry = try DirectoryObjectEntry.fetchSingleRow(db: db, where: DirectoryObjectEntry.fileGroupUUIDField.description == download.fileGroupUUID) else {
            throw SyncServerError.noObject
        }
        
        guard let sharingEntry = try SharingEntry.fetchSingleRow(db: db, where: SharingEntry.sharingGroupUUIDField.description == objectEntry.sharingGroupUUID) else {
            throw SyncServerError.sharingGroupNotFound
        }
        
        guard !sharingEntry.deleted else {
            throw SyncServerError.sharingGroupDeleted
        }

        guard !(try DirectoryFileEntry.anyFileIsDeleted(fileUUIDs: fileUUIDsToDownload, db: db)) else {
            throw SyncServerError.attemptToQueueADeletedFile
        }
            
        // Make sure all files in the downloads have the declared file group.
        for file in download.downloads {
            guard let fileEntry = try DirectoryFileEntry.fetchSingleRow(db: db, where: DirectoryFileEntry.fileUUIDField.description == file.uuid) else {
                throw SyncServerError.internalError("Cannot find fileUUID")
            }

            guard fileEntry.fileGroupUUID == download.fileGroupUUID else {
                throw SyncServerError.fileNotDeclared
            }
        }
                
        // If there is an active download for this fileGroupUUID, then this download will be locally queued for later processing. If there is not one, we'll trigger the download now.
        let activeDownloadsForThisFileGroup = try DownloadObjectTracker.anyDownloadsWith(status: .downloading, fileGroupUUID: download.fileGroupUUID, db: db)
                
        // Create a DownloadObjectTracker and DownloadFileTracker(s)
        let (newObjectTrackerId, _, fileTrackers) = try createNewTrackers(fileGroupUUID: download.fileGroupUUID, downloads: download.downloads)

        guard !activeDownloadsForThisFileGroup else {
            // There are active downloads for this file group.
            delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.downloadQueue(self, event: .queued(fileGroupUUID: download.fileGroupUUID))
            }
            return
        }
        
        // Can trigger these downloads.
        for (download, tracker) in zip(download.downloads, fileTrackers) {
            try singleDownload(fileUUID: download.uuid, fileVersion: download.fileVersion, tracker: tracker, objectTrackerId: newObjectTrackerId, sharingGroupUUID: objectEntry.sharingGroupUUID)
        }
    }
    
    // Add a new tracker into DownloadObjectTracker, and one for each new download.
    // The order and length of the elements returned in the [DownloadFileTracker] array is the same as in the downloads array.
    private func createNewTrackers<DWL: FileShouldBeDownloaded>(fileGroupUUID: UUID, downloads: [DWL]) throws -> (newObjectTrackerId: Int64, DownloadObjectTracker, [DownloadFileTracker]) {
    
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

