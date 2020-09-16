
import Foundation
import SQLite

extension SyncServer {
    func queueHelper<DECL: DeclarableObject, DWL: DownloadableFile>(downloads: Set<DWL>, declaration: DECL) throws {
        guard downloads.count > 0 else {
            throw SyncServerError.noUploads
        }
        
        guard declaration.declaredFiles.count > 0 else {
            throw SyncServerError.noDeclaredFiles
        }
        
        // Make sure all files in the uploads and declarations have distinct uuid's
        guard DWL.hasDistinctUUIDs(in: downloads) else {
            throw SyncServerError.uploadsDoNotHaveDistinctUUIDs
        }
        
        guard DECL.DeclaredFile.hasDistinctUUIDs(in: declaration.declaredFiles) else {
            throw SyncServerError.declaredFilesDoNotHaveDistinctUUIDs
        }
            
        // Make sure all files in the uploads are in the declaration.
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
    }
}
