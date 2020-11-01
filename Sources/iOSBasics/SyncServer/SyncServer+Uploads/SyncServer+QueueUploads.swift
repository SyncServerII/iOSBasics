import Foundation
import SQLite
import ServerShared
import iOSShared

extension SyncServer {
    func queueHelper(upload: UploadableObject) throws {
        guard upload.uploads.count > 0 else {
            throw SyncServerError.noUploads
        }
        
        // Make sure all files in the uploads have distinct uuid's
        guard Set<UUID>(upload.uploads.map {$0.uuid}).count == upload.uploads.count else {
            throw SyncServerError.uploadsDoNotHaveDistinctUUIDs
        }
            
        // Make sure this exact object type was registered previously
        let declaredObject = try DeclaredObjectModel.lookup(upload: upload, db: db)

        if let objectEntry = try DirectoryObjectEntry.lookup(fileGroupUUID: upload.fileGroupUUID, db: db) {
        
            #warning("Make sure the object matches the one we're uploading. E.g., same sharing group?")
            
            // This specific object has been uploaded before-- upload again.
            try uploadExisting(upload: upload, objectModel: declaredObject, objectEntry: objectEntry)
        }
        else {
            // This specific object has not been uploaded before-- upload for the first time.
            try uploadNew(upload: upload, objectType: declaredObject)
        }

        // Are there active uploads for this file group? Then defer. Otherwise, start it.
        
        // Is this the first upload for this file group?
        
        // We should never try to upload a file that has an index (db info) from the server, but hasn't yet been downloaded. This doesn't seem to reflect a valid state: How can a user request an upload for a file they haven't yet seen?
        
        

        /*
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
        */
    }
    
    // Add a new tracker into UploadObjectTracker, and one for each new upload.
    private func createNewTrackers(fileGroupUUID: UUID, cloudStorageType: CloudStorageType, uploads: [UploadableFile]) throws -> (newObjectTrackerId: Int64, UploadObjectTracker) {
    
        let newObjectTracker = try UploadObjectTracker(db: db, fileGroupUUID: fileGroupUUID)
        try newObjectTracker.insert()
        
        guard let newObjectTrackerId = newObjectTracker.id else {
            throw SyncServerError.internalError("No object tracker id")
        }
        
        logger.debug("newObjectTrackerId: \(newObjectTrackerId)")
        
        // Create a new `UploadFileTracker` for each file we're uploading.
        for file in uploads {
            let newFileTracker = try UploadFileTracker.create(file: file, cloudStorageType: cloudStorageType, objectTrackerId: newObjectTrackerId, config: configuration.temporaryFiles, hashingManager: hashingManager, db: db)
            logger.debug("newFileTracker: \(String(describing: newFileTracker.id))")
        }
        
        return (newObjectTrackerId, newObjectTracker)
    }
    
    // This is an existing upload for the file group.
    private func uploadExisting(upload: UploadableObject, objectModel: DeclaredObjectModel, objectEntry: DirectoryObjectEntry.ObjectInfo) throws {
    
        let existingFileLabels = Set<String>(objectEntry.allEntries.map {$0.fileLabel})
        let currentUploadFileLabels = Set<String>(upload.uploads.map {$0.fileLabel})
        
        // All uploads need to be v0 or non-v0: Either all fileLabel's in the current upload are in the existing fileLabel's, or none of them are.
        let allVN = existingFileLabels.union(currentUploadFileLabels).count == currentUploadFileLabels.count
        let allV0 = existingFileLabels.intersection(currentUploadFileLabels).count == 0
        
        guard allVN || allV0 else {
            throw SyncServerError.attemptToQueueUploadOfVNAndV0Files
        }
        
        if allV0 {
            // Need to make sure that all `currentUploadFileLabels` are in the DeclaredObjectModel.
            let declarationFileLabels = Set<String>(try objectModel.getFiles().map {$0.fileLabel})
            guard declarationFileLabels.union(currentUploadFileLabels).count == declarationFileLabels.count else {
                throw SyncServerError.someFileLabelsNotInDeclaredObject
            }
        }
            
        // This is the upload of an existing file group. Are there any files currently uploading for this file group? If yes, queued for later. If yes, can trigger these now.
    }
    
    // This is the first upload for the file group. i.e., the first upload for this specific object.
    private func uploadNew(upload: UploadableObject, objectType: DeclaredObjectModel) throws {
        // Need directory entries for this new specific object instance.
        let objectEntry = try DirectoryObjectEntry.createNewInstance(upload: upload, objectType: objectType, db: db)
        
        // The user must do at least one `sync` call prior to queuing an upload or this may throw an error.
        let cloudStorageType = try cloudStorageTypeForNewFile(sharingGroupUUID: upload.sharingGroupUUID)
        
        // Every new upload needs new upload trackers.
        let (_, newObjectTracker) = try createNewTrackers(fileGroupUUID: upload.fileGroupUUID, cloudStorageType: cloudStorageType, uploads: upload.uploads)
        
        // Since this is the first upload for a new object instance, all uploads are v0.
        try newObjectTracker.update(setters: UploadObjectTracker.v0UploadField.description <- true)

        for (index, uploadFile) in upload.uploads.enumerated() {
            try singleUpload(objectType: objectType, objectTracker: newObjectTracker, objectEntry: objectEntry, fileLabel: uploadFile.fileLabel, fileUUID: uploadFile.uuid, v0Upload: true, uploadIndex: Int32(index + 1), uploadCount: Int32(upload.uploads.count))
        }
    }
}
