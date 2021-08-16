
import Foundation
import iOSShared
import SQLite
import ServerShared

extension SyncServer {
    func singleDownload(fileTracker: BackgroundCacheFileTracker, fileUUID: UUID, fileVersion: FileVersionInt, tracker: DownloadFileTracker, objectTrackerId: Int64, sharingGroupUUID: UUID) throws {
    
        guard configuration.allowUploadDownload else {
            logger.warning("allowUploadDownload is false; not doing download.")
            return
        }
    
        let file = FileObject(fileUUID: fileUUID.uuidString, fileVersion: fileVersion, trackerId: objectTrackerId)
        
        if let error = api.downloadFile(fileTracker: fileTracker, file: file, sharingGroupUUID: sharingGroupUUID.uuidString) {
            // Going to keep going here despite the error because (a) we might have started downloads, and (b) we can restart these as part of our normal error/restart process.
            delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.userEvent(self, event: .error(error))
            }
            
            return
        }
        
        let expiry = try DownloadFileTracker.expiryDate(expiryDuration: configuration.expiryDuration)
        try tracker.update(setters:
            DownloadFileTracker.statusField.description <- .downloading,
            DownloadFileTracker.expiryField.description <- expiry)
    }
}
