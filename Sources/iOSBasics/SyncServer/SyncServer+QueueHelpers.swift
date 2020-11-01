
import Foundation

extension SyncServer {
    /*
    // Throws an error if the declared object cannot be queued.
    func declaredObjectCanBeQueued<DECL: DeclarableObject>(declaration: DECL, declaredObject:DeclaredObjectModel) throws {
        guard declaredObject.compare(to: declaration) else {
            throw SyncServerError.declarationDifferentThanSyncedObject("Declared object differs from given one.")
        }
        
        // Lookup and compare declared files against the `DeclaredFileModel`'s in the database.
        let declaredFilesInDatabase = try DeclaredFileModel.lookupModels(for: declaration.declaredFiles, inFileGroupUUID: declaration.fileGroupUUID, db: db)
        
        guard try DirectoryEntry.isOneEntryForEach(declaredModels: declaredFilesInDatabase, db: db) else {
            throw SyncServerError.declarationDifferentThanSyncedObject(
                    "DirectoryEntry missing.")
        }
        
        let fileUUIDs = declaredFilesInDatabase.map { $0.uuid }
        guard !(try DirectoryEntry.anyFileIsDeleted(fileUUIDs: fileUUIDs, db: db)) else {
            throw SyncServerError.attemptToQueueADeletedFile
        }
    }
    */
}
