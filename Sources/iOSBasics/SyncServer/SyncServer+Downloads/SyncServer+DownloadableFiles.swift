
import Foundation
import SQLite
import ServerShared

extension SyncServer {
    func filesNeedingDownloadHelper(sharingGroupUUID: UUID) throws -> [ObjectNeedsDownload] {
        let objectEntries = try DirectoryObjectEntry.fetch(db: db, where:
            DirectoryObjectEntry.sharingGroupUUIDField.description == sharingGroupUUID)
        guard objectEntries.count > 0 else {
            return []
        }
        
        var allDownloads = [DirectoryFileEntry]()
        
        let fileGroupUUIDs = objectEntries.map {$0.fileGroupUUID}
        for fileGroupUUID in fileGroupUUIDs {
            let fileEntries = try DirectoryFileEntry.fetch(db: db, where:
                DirectoryFileEntry.fileGroupUUIDField.description == fileGroupUUID)
            let downloads = fileEntries.filter { $0.fileState == .needsDownload }
            allDownloads += downloads
        }

        guard allDownloads.count > 0 else {
            // This is *not* an error case. There can be DirectoryFileEntry's, but that don't indicate a need for downloading.
            return []
        }
        
        var result = [ObjectNeedsDownload]()
        
        let downloadGroups = Partition.array(allDownloads, using: \.fileGroupUUID)
        
        for downloadGroup in downloadGroups {
            let first = downloadGroup[0]
            
            let fileDownloads = try downloadGroup.map { file -> FileNeedsDownload in
                guard let serverFileVersion = file.serverFileVersion else {
                    throw SyncServerError.internalError("Nil serverFileVersion")
                }
                
                return FileNeedsDownload(uuid: file.fileUUID, fileVersion: serverFileVersion, fileLabel: file.fileLabel)
            }
            
            result += [ObjectNeedsDownload(fileGroupUUID: first.fileGroupUUID, downloads: fileDownloads)]
        }

        return result
    }
    
    func markAsDownloadedHelper<DWL: FileShouldBeDownloaded>(file: DWL) throws {
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
}

extension UUID: Comparable {
    public static func <(lhs: UUID, rhs: UUID) -> Bool {
        return lhs.uuidString < rhs.uuidString
    }
}

