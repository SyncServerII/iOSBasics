
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
    
    func fileInfoHelper(fileUUID: UUID) throws -> FileAttributes? {
        guard let fileEntry = try DirectoryFileEntry.fetchSingleRow(db: db, where: DirectoryFileEntry.fileUUIDField.description == fileUUID) else {
            return nil
        }
                
        return FileAttributes(fileVersion: fileEntry.fileVersion, serverVersion: fileEntry.serverFileVersion, creationDate: fileEntry.creationDate, updateDate: fileEntry.updateDate)
    }
    
    func fileGroupInfoHelper(fileGroupUUID: UUID) throws -> FileGroupAttributes? {
        guard let objectInfo = try DirectoryObjectEntry.lookup(fileGroupUUID: fileGroupUUID, db: db) else {
            return nil
        }
        
        let files = objectInfo.allFileEntries.map {
            FileGroupAttributes.FileAttributes(fileLabel: $0.fileLabel, fileUUID: $0.fileUUID)
        }
        
        // This should never happen, but check for it to be safe.
        guard files.count > 0 else {
            throw DatabaseError.noObject
        }
        
        return FileGroupAttributes(files: files)
    }
}
