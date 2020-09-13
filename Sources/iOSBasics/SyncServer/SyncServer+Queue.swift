import Foundation
import SQLite
import ServerShared
import iOSShared

extension SyncServer {    
    func queueObject<DECL: DeclarableObject, UPL:UploadableFile>
        (declaration: DECL, uploads: Set<UPL>) throws {
        guard uploads.count > 0 else {
            throw SyncServerError.noUploads
        }
        
        guard declaration.declaredFiles.count > 0 else {
            throw SyncServerError.noDeclaredFiles
        }
        
        // Make sure all files in the uploads and declarations have distinct uuid's
        guard UPL.hasDistinctUUIDs(in: uploads) else {
            throw SyncServerError.uploadsDoNotHaveDistinctUUIDs
        }
        
        guard DECL.DeclaredFile.hasDistinctUUIDs(in: declaration.declaredFiles) else {
            throw SyncServerError.declaredFilesDoNotHaveDistinctUUIDs
        }
            
        // Make sure all files in the uploads are in the declaration.
        for upload in uploads {
            let declaredFiles = declaration.declaredFiles.filter {$0.uuid == upload.uuid}
            guard declaredFiles.count == 1 else {
                throw SyncServerError.uploadNotInDeclaredFiles
            }
        }
        
        // See if this DeclaredObject has been registered before.
        let declaredObjects = try DeclaredObjectModel.fetch(db: db,
            where: declaration.fileGroupUUID == DeclaredObjectModel.fileGroupUUIDField.description)
        let newFiles: Bool
        
        switch declaredObjects.count {
        case 0:
            newFiles = true
            
            // New, locally created, declarations must have a non-nil object type.
            guard let _ = declaration.objectType else {
                throw SyncServerError.noObjectTypeForNewDeclaration
            }
            
            try DeclaredObjectModel.createModels(from: declaration, db: db)
            try DirectoryEntry.createEntries(for: declaration.declaredFiles, db: db)
            
        case 1:
            newFiles = false
            
            // Have exactly one declaredObject
            let declaredObject = declaredObjects[0]

            // Already have registered the DeclarableObject
            // Need to compare this one against the one in the database.

            guard declaredObject.compare(to: declaration) else {
                throw SyncServerError.declarationDifferentThanSyncedObject("Declared object differs from given one.")
            }
            
            // Lookup and compare declared files against the `DeclaredFileModel`'s in the database.
            let declaredFilesInDatabase = try DeclaredFileModel.lookupModels(for: declaration.declaredFiles, inFileGroupUUID: declaration.fileGroupUUID, db: db)
            
            guard try DirectoryEntry.isOneEntryForEach(declaredModels: declaredFilesInDatabase, db: db) else {
                throw SyncServerError.declarationDifferentThanSyncedObject(
                        "DirectoryEntry missing.")
            }
            
            guard !(try DirectoryEntry.anyFileIsDeleted(declaredModels: declaredFilesInDatabase, db: db)) else {
                throw SyncServerError.attemptToQueueADeletedFile
            }

        default:
            throw SyncServerError.internalError("Had two registered DeclaredObject's for the same fileGroupUUID: fileGroupUUID: \(declaration.fileGroupUUID)")
        }
        
        // If there is an active upload for this fileGroupUUID, then this upload will be locally queued for later processing. If there is not one, we'll trigger the upload now.
        let activeUploadsForThisFileGroup = try UploadObjectTracker.anyUploadsWith(status: .uploading, fileGroupUUID: declaration.fileGroupUUID, db: db)
                
        // Create an UploadObjectTracker and UploadFileTracker(s)
        let (newObjectTrackerId, newObjectTracker) = try createNewTrackers(fileGroupUUID: declaration.fileGroupUUID, declaration: declaration, uploads: uploads)

        guard !activeUploadsForThisFileGroup else {
            // There are active uploads for this file group.
            delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.uploadQueued(self, declObjectId: declaration.declObjectId)
            }
            return
        }
        
        if newFiles {
            let uploadCount = Int32(uploads.count)
            
            // `v0Upload` is simple here: Because all files are new, we must be uploading v0 for all of them.
            let v0Upload = true
            
            try newObjectTracker.update(setters:
                UploadObjectTracker.v0UploadField.description <- v0Upload)
                
            for (uploadIndex, file) in uploads.enumerated() {
                try singleUpload(declaration: declaration, fileUUID: file.uuid, v0Upload: v0Upload, objectTrackerId: newObjectTrackerId, uploadIndex: Int32(uploadIndex + 1), uploadCount: uploadCount)
            }
        }
        else {
            try triggerUploads()
        }
    }
    
    // Add a new tracker into UploadObjectTracker, and one for each new upload.
    private func createNewTrackers<DECL: DeclarableObject, UPL: UploadableFile>(fileGroupUUID: UUID, declaration: DECL, uploads: Set<UPL>) throws -> (newObjectTrackerId: Int64, UploadObjectTracker) {
    
        let newObjectTracker = try UploadObjectTracker(db: db, fileGroupUUID: fileGroupUUID)
        try newObjectTracker.insert()
        
        guard let newObjectTrackerId = newObjectTracker.id else {
            throw SyncServerError.internalError("No object tracker id")
        }
        
        logger.debug("newObjectTrackerId: \(newObjectTrackerId)")
        
        // Create a new `UploadFileTracker` for each file we're uploading.
        for file in uploads {
            let newFileTracker = try UploadFileTracker.create(file: file, in: declaration, newObjectTrackerId: newObjectTrackerId, config: configuration.temporaryFiles, hashingManager: hashingManager, db: db)
            logger.debug("newFileTracker: \(String(describing: newFileTracker.id))")
        }
        
        return (newObjectTrackerId, newObjectTracker)
    }
}
