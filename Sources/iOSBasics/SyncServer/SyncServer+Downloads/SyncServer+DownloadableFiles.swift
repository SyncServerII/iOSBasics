
import Foundation
import SQLite
import ServerShared

extension SyncServer {
    func filesNeedingDownloadHelper(sharingGroupUUID: UUID, includeGone: Bool) throws -> [DownloadObject] {
        let objectEntries = try DirectoryObjectEntry.fetch(db: db, where:
            DirectoryObjectEntry.sharingGroupUUIDField.description == sharingGroupUUID &&
            DirectoryObjectEntry.deletedLocallyField.description == false &&
            DirectoryObjectEntry.deletedOnServerField.description == false)
        guard objectEntries.count > 0 else {
            return []
        }
        
        var allDownloads = [DirectoryFileEntry]()
        
        let fileGroupUUIDs = objectEntries.map {$0.fileGroupUUID}
        for fileGroupUUID in fileGroupUUIDs {
            let fileEntries = try DirectoryFileEntry.fetch(db: db, where:
                DirectoryFileEntry.fileGroupUUIDField.description == fileGroupUUID)
            let downloads = fileEntries.filter
                { $0.fileState(includeGone: includeGone) == .needsDownload }
            allDownloads += downloads
        }

        guard allDownloads.count > 0 else {
            // This is *not* an error case. There can be DirectoryFileEntry's, but that don't indicate a need for downloading.
            return []
        }
        
        var result = [DownloadObject]()
        
        let downloadGroups = Partition.array(allDownloads, using: \.fileGroupUUID)
        
        for downloadGroup in downloadGroups {
            let first = downloadGroup[0]

            // To account for an issue I'm seeing on 3/10/21 where an object tracker exists but file trackers don't.
            try DownloadObjectTracker.cleanupIfNeeded(fileGroupUUID: first.fileGroupUUID, db: db)
        
            // Is this fileGroupUUID currently being downloaded or queued for download?
            let existingObjectTracker = try DownloadObjectTracker.fetch(db: db, where: DownloadObjectTracker.fileGroupUUIDField.description == first.fileGroupUUID)
            guard existingObjectTracker.count == 0 else {
                continue
            }

            guard let creationDate = (downloadGroup.map { $0.creationDate }.min()) else {
                throw SyncServerError.internalError("Could not get creationDate")
            }
            
            let fileDownloads = try downloadGroup.map { file -> DownloadFile in
                guard let serverFileVersion = file.serverFileVersion else {
                    throw SyncServerError.internalError("Nil serverFileVersion")
                }
                
                return DownloadFile(uuid: file.fileUUID, fileVersion: serverFileVersion, fileLabel: file.fileLabel)
            }
            
            result += [DownloadObject(sharingGroupUUID: sharingGroupUUID, fileGroupUUID: first.fileGroupUUID, creationDate: creationDate, downloads: fileDownloads)]
        }

        return result
    }
    
    // Returns nil if the file (a) doesn't need download or (b) if it's currently being downloaded or is queued for download. Returns non-nil otherwise.
    func objectNeedsDownloadHelper(object fileGroupUUID: UUID, includeGone: Bool) throws -> DownloadObject? {
        let fileEntries = try DirectoryFileEntry.fetch(db: db, where:
            DirectoryFileEntry.fileGroupUUIDField.description == fileGroupUUID &&
            DirectoryFileEntry.deletedLocallyField.description == false &&
            DirectoryFileEntry.deletedOnServerField.description == false)
        guard fileEntries.count > 0 else {
            // An existing file group must have at least one file entry.
            throw DatabaseError.noObject
        }
        
        let downloads = fileEntries.filter
            { $0.fileState(includeGone: includeGone) == .needsDownload }
        
        if downloads.count == 0 {
            // No files needing download for this file group.
            return nil
        }
        
        // To account for an issue I'm seeing on 3/10/21 where an object tracker exists but file trackers don't.
        try DownloadObjectTracker.cleanupIfNeeded(fileGroupUUID: fileGroupUUID, db: db)
        
        let existingObjectTracker = try DownloadObjectTracker.fetch(db: db, where: DownloadObjectTracker.fileGroupUUIDField.description == fileGroupUUID)
        
        guard existingObjectTracker.count == 0 else {
            // There are existing download trackers for this file group.
            return nil
        }
        
        guard let objectEntry = try DirectoryObjectEntry.fetchSingleRow(db: db, where:
            DirectoryObjectEntry.fileGroupUUIDField.description == fileGroupUUID) else {
            // This is an error: There must be an object if there are file for the file group.
            throw DatabaseError.noObject
        }
              
        guard let creationDate = (downloads.map { $0.creationDate }.min()) else {
            throw SyncServerError.internalError("Could not get creationDate")
        }

        let fileDownloads = try downloads.map { file -> DownloadFile in
            guard let serverFileVersion = file.serverFileVersion else {
                throw SyncServerError.internalError("Nil serverFileVersion")
            }

            return DownloadFile(uuid: file.fileUUID, fileVersion: serverFileVersion, fileLabel: file.fileLabel)
        }
            
        return DownloadObject(sharingGroupUUID: objectEntry.sharingGroupUUID, fileGroupUUID: fileGroupUUID, creationDate: creationDate, downloads: fileDownloads)
    }
    
    func markAsDownloadedHelper<DWL: DownloadableFile>(file: DWL) throws {
        guard let entry = try DirectoryFileEntry.fetchSingleRow(db: db, where: DirectoryFileEntry.fileUUIDField.description == file.uuid) else {
            throw SyncServerError.noObject
        }
        
        guard let serverFileVersion = entry.serverFileVersion else {
            throw SyncServerError.fileNotDownloaded
        }
        
        guard file.fileVersion >= 0 && file.fileVersion <= serverFileVersion else {
            throw SyncServerError.badFileVersion
        }
        
        try entry.update(setters:
            DirectoryFileEntry.fileVersionField.description <- file.fileVersion)
    }
    
    func markAsNotDownloadedHelper(file: FileNotDownloaded) throws {
        guard let entry = try DirectoryFileEntry.fetchSingleRow(db: db, where: DirectoryFileEntry.fileUUIDField.description == file.uuid) else {
            throw SyncServerError.noObject
        }
        
        try entry.update(setters:
            DirectoryFileEntry.fileVersionField.description <- nil)
    }
    
    func markAsDownloadedHelper<DWL: DownloadableObject>(object: DWL) throws {
        guard let _ = try DirectoryObjectEntry.fetchSingleRow(db: db, where: DirectoryObjectEntry.fileGroupUUIDField.description == object.fileGroupUUID) else {
            throw SyncServerError.noObject
        }
        
        for file in object.downloads {
            try markAsDownloadedHelper(file: file)
        }
        
        delegator { delegate in
            delegate.objectMarked(self, withDownloadState: .downloaded, fileGroupUUID: object.fileGroupUUID)
        }
    }
    
    func markAsNotDownloadedHelper<DWL: ObjectNotDownloaded>(object: DWL) throws {
        guard let _ = try DirectoryObjectEntry.fetchSingleRow(db: db, where: DirectoryObjectEntry.fileGroupUUIDField.description == object.fileGroupUUID) else {
            throw SyncServerError.noObject
        }
        
        for file in object.downloads {
            try markAsNotDownloadedHelper(file: file)
        }
        
        delegator { delegate in
            delegate.objectMarked(self, withDownloadState: .notDownloaded, fileGroupUUID: object.fileGroupUUID)
        }
    }
}

extension UUID: Comparable {
    public static func <(lhs: UUID, rhs: UUID) -> Bool {
        return lhs.uuidString < rhs.uuidString
    }
}

