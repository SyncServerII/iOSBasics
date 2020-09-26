import Foundation
import SQLite
import ServerShared
import iOSShared

extension SyncServer {    
    func queueHelper<DECL: DeclarableObject, UPL:UploadableFile>
        (uploads: Set<UPL>, declaration: DECL) throws {
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
        
        #warning("Seems like we ought to check the SharingEntry and make sure the sharing group in the declaration is not deleted")
            
        // Make sure all files in the uploads are in the declaration.
        for upload in uploads {
            let declaredFiles = declaration.declaredFiles.filter {$0.uuid == upload.uuid}
            guard declaredFiles.count == 1 else {
                throw SyncServerError.fileNotDeclared
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
            try DirectoryEntry.createEntries(for: declaration.declaredFiles, fileGroupUUID: declaration.fileGroupUUID, sharingGroupUUID: declaration.sharingGroupUUID, db: db)
            
        case 1:
            newFiles = false
            
            // Have exactly one declaredObject
            let declaredObject = declaredObjects[0]

            // Already have registered the DeclarableObject
            // Need to compare this one against the one in the database.
            try declaredObjectCanBeQueued(declaration: declaration, declaredObject:declaredObject)
            
            // We should never try to upload a file that has an index (db info) from the server, but hasn't yet been downloaded. This doesn't seem to reflect a valid state: How can a user request an upload for a file they haven't yet seen?
            let entriesForUploads = try DirectoryEntry.lookupFor(uploadables: uploads, db: db)
            for entry in entriesForUploads {
                if entry.fileVersion == nil && entry.serverFileVersion != nil {
                    throw SyncServerError.attemptToQueueAFileThatHasNotBeenDownloaded
                }
            }

        default:
            throw SyncServerError.internalError("Had two registered DeclaredObject's for the same fileGroupUUID: fileGroupUUID: \(declaration.fileGroupUUID)")
        }
        
        // If there is an active upload for this fileGroupUUID, then this upload will be locally queued for later processing. If there is not one, we'll trigger the upload now.
        let activeUploadsForThisFileGroup = try UploadObjectTracker.anyUploadsWith(status: .uploading, fileGroupUUID: declaration.fileGroupUUID, db: db)

        // The user must do at least one `sync` call prior to queuing an upload or this throws an error.
        let cloudStorageType = try cloudStorageTypeForNewFile(sharingGroupUUID: declaration.sharingGroupUUID)
        
        // Create an UploadObjectTracker and UploadFileTracker(s)
        let (newObjectTrackerId, newObjectTracker) = try createNewTrackers(fileGroupUUID: declaration.fileGroupUUID, cloudStorageType: cloudStorageType, declaration: declaration, uploads: uploads)

        guard !activeUploadsForThisFileGroup else {
            // There are active uploads for this file group.
            delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.uploadQueue(self, event: .queued(fileGroupUUID: declaration.fileGroupUUID))
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
    private func createNewTrackers<DECL: DeclarableObject, UPL: UploadableFile>(fileGroupUUID: UUID, cloudStorageType: CloudStorageType, declaration: DECL, uploads: Set<UPL>) throws -> (newObjectTrackerId: Int64, UploadObjectTracker) {
    
        let newObjectTracker = try UploadObjectTracker(db: db, fileGroupUUID: fileGroupUUID)
        try newObjectTracker.insert()
        
        guard let newObjectTrackerId = newObjectTracker.id else {
            throw SyncServerError.internalError("No object tracker id")
        }
        
        logger.debug("newObjectTrackerId: \(newObjectTrackerId)")
        
        // Create a new `UploadFileTracker` for each file we're uploading.
        for file in uploads {
            let newFileTracker = try UploadFileTracker.create(file: file, in: declaration, cloudStorageType: cloudStorageType, newObjectTrackerId: newObjectTrackerId, config: configuration.temporaryFiles, hashingManager: hashingManager, db: db)
            logger.debug("newFileTracker: \(String(describing: newFileTracker.id))")
        }
        
        return (newObjectTrackerId, newObjectTracker)
    }
}
