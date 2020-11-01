
import Foundation
import SQLite
import ServerShared

/*
extension SyncServer {
    func filesNeedingDownloadHelper(sharingGroupUUID: UUID) throws -> [(ObjectDeclaration, Set<FileDownload>)] {
    
        let entries = try DirectoryEntry.fetch(db: db, where:
            DirectoryEntry.sharingGroupUUIDField.description == sharingGroupUUID)
        guard entries.count > 0 else {
            return []
        }
        
        let download = entries.filter { $0.fileState == .needsDownload }
        
        guard download.count > 0 else {
            // This is *not* an error case. There can be DirectoryEntry's, but that don't indicate a need for downloading.
            return []
        }
        
        var result = [(ObjectDeclaration, Set<FileDownload>)]()
        
        let downloadGroups = Partition.array(download, using: \.fileGroupUUID)
        
        for downloadGroup in downloadGroups {
            let first = downloadGroup[0]
            let declaredObject:ObjectDeclaration = try DeclaredObjectModel.lookupDeclarableObject(fileGroupUUID: first.fileGroupUUID, db: db)
            
            var downloads = Set<FileDownload>()
            for entry in downloadGroup {
                guard let serverFileVersion = entry.serverFileVersion else {
                    throw SyncServerError.internalError("Nil serverFileVersion")
                }
                
                let download = FileDownload(uuid: entry.fileUUID, fileVersion: serverFileVersion)
                downloads.insert(download)
            }
            
            let declaredFiles = Set<FileDeclaration>(declaredObject.declaredFiles.map {
                return FileDeclaration(uuid: $0.uuid, mimeType: $0.mimeType, appMetaData: $0.appMetaData, changeResolverName: $0.changeResolverName)
            })
            
            let declaration = ObjectDeclaration(fileGroupUUID: declaredObject.fileGroupUUID, objectType: declaredObject.objectType, sharingGroupUUID: declaredObject.sharingGroupUUID, declaredFiles: declaredFiles)
            
            result += [(declaration, downloads)]
        }

        return result
    }
    
    func markAsDownloadedHelper<DWL: DownloadableFile>(file: DWL) throws {
        guard let entry = try DirectoryEntry.fetchSingleRow(db: db, where: DirectoryEntry.fileUUIDField.description == file.uuid) else {
            throw SyncServerError.noObject
        }
        
        guard let serverFileVersion = entry.serverFileVersion else {
            throw SyncServerError.fileNotDownloaded
        }
        
        guard file.fileVersion >= 0 && file.fileVersion <= serverFileVersion else {
            throw SyncServerError.badFileVersion
        }
        
        try entry.update(setters:
            DirectoryEntry.fileVersionField.description <- file.fileVersion)
    }
}

extension UUID: Comparable {
    public static func <(lhs: UUID, rhs: UUID) -> Bool {
        return lhs.uuidString < rhs.uuidString
    }
}
*/
