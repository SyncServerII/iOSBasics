import Foundation
import SQLite

extension SyncServer {
    // Re-check of queued downloads.
    func triggerDownloads() throws {
        let notStartedDownloads = try DownloadObjectTracker.allDownloadsWith(status: .notStarted, db: db)
        guard notStartedDownloads.count > 0 else {
            self.delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.downloadQueue(self, event: .sync(numberDownloadsStarted: 0))
            }
            return
        }
        
        // What downloads are currently in-progress?
        let inProgress = try DownloadObjectTracker.allDownloadsWith(status: .downloading, db: db)
        let fileGroupsInProgress = Set<UUID>(inProgress.map { $0.object.fileGroupUUID })
        
        // These are the objects we want to `exclude` from downloading. Start off with the file groups actively downloading. Don't want parallel downloads for the same file group.
        var currentObjects = fileGroupsInProgress
        
        var toTrigger = [DownloadObjectTracker.DownloadWithStatus]()
        
        for download in notStartedDownloads {
            // Don't want parallel download for the same declared object.
            guard !currentObjects.contains(download.object.fileGroupUUID) else {
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
