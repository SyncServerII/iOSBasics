
import Foundation
import SQLite
import iOSShared

extension SyncServer {
    func isQueuedHelper(_ queueType: QueueType, fileGroupUUID: UUID) throws -> Bool {
        let tracker: AnyObject?
        
        switch queueType {
        case .deletion:
            tracker = try UploadDeletionTracker.fetchSingleRow(db: db, where: UploadDeletionTracker.uuidField.description == fileGroupUUID &&
                UploadDeletionTracker.deletionTypeField.description == .fileGroupUUID)
            
        case .download:
            tracker = try DownloadObjectTracker.fetchSingleRow(db: db, where: DownloadObjectTracker.fileGroupUUIDField.description == fileGroupUUID)
            
        case .upload:
            tracker = try UploadObjectTracker.fetchSingleRow(db: db, where: UploadObjectTracker.fileGroupUUIDField.description == fileGroupUUID)
        }
        
        return tracker != nil
    }
    
    func numberQueuedHelper(_ queueType: QueueType) throws -> Int {
        switch queueType {
        case .deletion:
            let tracker = try UploadDeletionTracker.fetch(db: db)
            return tracker.count
            
        case .download:
            let tracker = try DownloadObjectTracker.fetch(db: db)
            return tracker.count
            
        case .upload:
            let tracker = try UploadObjectTracker.fetch(db: db)
            return tracker.count
        }
    }
    
    func fileInfoHelper(fileUUID: UUID) throws -> FileAttributes {
        guard let fileEntry = try DirectoryFileEntry.fetchSingleRow(db: db, where: DirectoryFileEntry.fileUUIDField.description == fileUUID) else {
            throw DatabaseError.noObject
        }
                
        return FileAttributes(fileVersion: fileEntry.fileVersion, serverVersion: fileEntry.serverFileVersion)
    }
}
