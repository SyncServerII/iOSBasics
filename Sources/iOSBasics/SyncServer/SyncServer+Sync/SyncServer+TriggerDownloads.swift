import Foundation
import SQLite

extension SyncServer {
    // Re-check of queued downloads.
    func triggerDownloads() throws {
        // What DownloadObjectTracker's have some files not started?
        let notStartedDownloads = try DownloadObjectTracker.downloadsWith(status: .notStarted, scope: .some, db: db)
        guard notStartedDownloads.count > 0 else {
            self.delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.downloadQueue(self, event: .sync(numberDownloadsStarted: 0))
            }
            return
        }
        
        // What downloads are currently completely in-progress?
        let inProgress = try DownloadObjectTracker.downloadsWith(status: .downloading, scope: .all, db: db)
        let fileGroupsInProgress = Set<UUID>(inProgress.map { $0.object.fileGroupUUID })
        
        // These are the objects we want to `exclude` from downloading. Start off with the file groups actively downloading. Don't want parallel downloads for the same file group.
        var currentObjects = fileGroupsInProgress
        
        var toTrigger = [DownloadObjectTracker.DownloadWithStatus]()
        
        for download in notStartedDownloads {
            // Don't want parallel download for the same declared object.
            guard !currentObjects.contains(download.object.fileGroupUUID) else {
                continue
            }
            
            // And, uploads take priority over downloads for a specific object.
            // See https://github.com/SyncServerII/Neebla/issues/25#issuecomment-898940988
            let uploadObjectTrackers = try UploadObjectTracker.fetch(db: db, where: UploadObjectTracker.fileGroupUUIDField.description == download.object.fileGroupUUID)
            let pendingUploads = uploadObjectTrackers.count > 0
            guard !pendingUploads else {
                continue
            }
            
            currentObjects.insert(download.object.fileGroupUUID)
            toTrigger += [download]
        }
        
        guard toTrigger.count > 0 else {
            self.delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.downloadQueue(self, event: .sync(numberDownloadsStarted: 0))
            }
            return
        }
        
        // Now can actually trigger the downloads.
        
        for downloadObject in toTrigger {
            guard let objectEntry = try DirectoryObjectEntry.fetchSingleRow(db: db, where: DirectoryObjectEntry.fileGroupUUIDField.description == downloadObject.object.fileGroupUUID) else {
                throw SyncServerError.internalError("Could not get DirectoryObjectEntry")
            }
            
            guard let objectId = downloadObject.object.id else {
                throw SyncServerError.internalError("Could not get object id")
            }
            
            for file in downloadObject.files {                
                try singleDownload(fileUUID: file.fileUUID, fileVersion: file.fileVersion, tracker: file, objectTrackerId: objectId, sharingGroupUUID: objectEntry.sharingGroupUUID)
            }
        }
        
        self.delegator { [weak self] delegate in
            guard let self = self else { return }
            delegate.downloadQueue(self, event: .sync(numberDownloadsStarted: UInt(toTrigger.count)))
        }
    }
}
