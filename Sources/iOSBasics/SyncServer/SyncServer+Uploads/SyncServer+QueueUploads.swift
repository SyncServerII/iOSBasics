import Foundation
import SQLite
import ServerShared
import iOSShared

extension SyncServer {
    private func matches(upload: UploadableObject, objectInfo: DirectoryObjectEntry.ObjectInfo) -> Bool {
        return upload.fileGroupUUID == objectInfo.objectEntry.fileGroupUUID &&
            upload.sharingGroupUUID == objectInfo.objectEntry.sharingGroupUUID
    }
    
    // Is the fileLabel/UUID combination in the fileEntries?
    private func fileLabelUUID(of upload: UploadableFile, in fileEntries:[DirectoryFileEntry]) throws -> DirectoryFileEntry? {
        let filter = fileEntries.filter {$0.fileLabel == upload.fileLabel}
        switch filter.count {
        case 0:
            // Before returning nil, make sure that the uuid in the upload doesn't occur in the fileEntries
            let uuids = fileEntries.filter {$0.fileUUID == upload.uuid}
            guard uuids.count == 0 else {
                throw SyncServerError.matchingUUIDButNoFileLabel
            }
            return nil
        case 1:
            // Before returning this fileEntry, make sure the uuid matches that in the upload.
            let fileEntry = filter[0]
            guard fileEntry.fileUUID == upload.uuid else {
                throw SyncServerError.noMatchingUUID
            }
            return fileEntry
        default:
            throw SyncServerError.tooManyObjects
        }
    }
    
    // Filters the `upload.uploads` of the passed `upload`.
    // Returns the `UploadableFile`'s that have not yet been uploaded. Neither the uuid or the fileLabel of the returned `UploadableFile`'s have been uploaded already.
    // For the non-returned UploadableFile`'s, they must match the fileLabel and uuid of the already uploaded file or an error is thrown.
    private func newUploads(upload: UploadableObject, objectInfo: DirectoryObjectEntry.ObjectInfo) throws -> [UploadableFile] {
        
        var v0Uploads = [UploadableFile]()
        
        for upload in upload.uploads {
            let fileEntry = try fileLabelUUID(of: upload, in: objectInfo.allFileEntries)
            if fileEntry == nil {
                // The fileLabel/UUID has not yet been uploaded.
                v0Uploads += [upload]
            }
        }
        
        return v0Uploads
    }
    
    func queueHelper(upload: UploadableObject) throws {
        guard upload.uploads.count > 0 else {
            throw SyncServerError.noUploads
        }
        
        guard let sharingEntry = try SharingEntry.fetchSingleRow(db: db, where: SharingEntry.sharingGroupUUIDField.description == upload.sharingGroupUUID) else {
            throw SyncServerError.sharingGroupNotFound
        }
        
        guard !sharingEntry.deleted else {
            throw SyncServerError.sharingGroupDeleted
        }

        // Make sure all files in the uploads have distinct uuid's
        guard Set<UUID>(upload.uploads.map {$0.uuid}).count == upload.uploads.count else {
            throw SyncServerError.uploadsDoNotHaveDistinctUUIDs
        }
            
        // Make sure this exact object type was registered previously
        let declaredObject = try DeclaredObjectModel.lookup(upload: upload, db: db)

        if let objectInfo = try DirectoryObjectEntry.lookup(fileGroupUUID: upload.fileGroupUUID, db: db) {
            // This object instance has been uploaded before.
            
            guard !objectInfo.objectEntry.deletedLocally && !objectInfo.objectEntry.deletedOnServer else {
                throw SyncServerError.attemptToQueueADeletedFile
            }

            guard matches(upload: upload, objectInfo: objectInfo) else {
                throw SyncServerError.internalError("Upload did not match objectInfo")
            }
            
            let v0Uploads = try newUploads(upload: upload, objectInfo: objectInfo)
            
            // If there is an active upload for this fileGroupUUID, then this upload will be locally queued for later processing. If there is not one, we'll trigger the upload now.
            let activeUploadsForThisFileGroup = try UploadObjectTracker.anyUploadsWith(status: .uploading, fileGroupUUID: objectInfo.objectEntry.fileGroupUUID, db: db)
        
            // All files must be either v0 or vN
            if v0Uploads.count == 0 {
                try uploadExisting(upload: upload, objectModel: declaredObject, objectEntry: objectInfo, activeUploadsForThisFileGroup: activeUploadsForThisFileGroup)
            }
            else if v0Uploads.count == upload.uploads.count {
                try uploadNew(upload: upload, objectType: declaredObject, objectEntryType: .existing(objectInfo.objectEntry), activeUploadsForThisFileGroup: activeUploadsForThisFileGroup)
            }
            else {
                throw SyncServerError.someUploadFilesV0SomeVN
            }
        }
        else {
            // This specific object has not been uploaded before-- upload for the first time.
            try uploadNew(upload: upload, objectType: declaredObject, objectEntryType: .newInstance, activeUploadsForThisFileGroup: false)
        }

        // We should never try to upload a file that has an index (db info) from the server, but hasn't yet been downloaded. This doesn't seem to reflect a valid state: How can a user request an upload for a file they haven't yet seen?
        
        /*

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
    
    // This is an upload for files already in the directory. i.e., a vN upload.
    private func uploadExisting(upload: UploadableObject, objectModel: DeclaredObjectModel, objectEntry: DirectoryObjectEntry.ObjectInfo, activeUploadsForThisFileGroup: Bool) throws {
    
        // These uploads must all have change resolvers since this is a vN upload.
        for upload in upload.uploads {
            let fileDeclaration = try objectModel.getFile(with: upload.fileLabel)
            guard let _ = fileDeclaration.changeResolverName else {
                throw SyncServerError.noChangeResolver
            }
        }
        
        // Every new upload needs new upload trackers.
        let (_, newObjectTracker) = try createNewTrackers(fileGroupUUID: upload.fileGroupUUID, cloudStorageType: objectEntry.objectEntry.cloudStorageType, uploads: upload.uploads)
        
        // This is an upload for existing file instances.
        try newObjectTracker.update(setters: UploadObjectTracker.v0UploadField.description <- false)
        
        if activeUploadsForThisFileGroup {
            delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.uploadQueue(self, event: .queued(fileGroupUUID: upload.fileGroupUUID))
            }
        } else {
            for (index, uploadFile) in upload.uploads.enumerated() {
                try singleUpload(objectType: objectModel, objectTracker: newObjectTracker, objectEntry: objectEntry.objectEntry, fileLabel: uploadFile.fileLabel, fileUUID: uploadFile.uuid, v0Upload: false, uploadIndex: Int32(index + 1), uploadCount: Int32(upload.uploads.count))
            }
        }
    }
    
    // This is either the first upload for the file group. i.e., the first upload for this specific object. OR, it's the first upload for only some of the files in the file group.
    private func uploadNew(upload: UploadableObject, objectType: DeclaredObjectModel, objectEntryType: DirectoryObjectEntry.ObjectEntryType, activeUploadsForThisFileGroup: Bool) throws {
        // The user must do at least one `sync` call prior to queuing an upload or this may throw an error.
        let cloudStorageType = try cloudStorageTypeForNewFile(sharingGroupUUID: upload.sharingGroupUUID)
        
        // Need directory entries for this new specific object instance.
        let objectEntry = try DirectoryObjectEntry.createNewInstance(upload: upload, objectType: objectType, objectEntryType: objectEntryType, cloudStorageType: cloudStorageType, db: db)
        
        // Every new upload needs new upload trackers.
        let (_, newObjectTracker) = try createNewTrackers(fileGroupUUID: upload.fileGroupUUID, cloudStorageType: cloudStorageType, uploads: upload.uploads)
        
        // Since this is the first upload for a new object instance or at least for the specific files of the object, all uploads are v0.
        try newObjectTracker.update(setters: UploadObjectTracker.v0UploadField.description <- true)

        if activeUploadsForThisFileGroup {
            delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.uploadQueue(self, event: .queued(fileGroupUUID: upload.fileGroupUUID))
            }
        }
        else {
            for (index, uploadFile) in upload.uploads.enumerated() {
                try singleUpload(objectType: objectType, objectTracker: newObjectTracker, objectEntry: objectEntry, fileLabel: uploadFile.fileLabel, fileUUID: uploadFile.uuid, v0Upload: true, uploadIndex: Int32(index + 1), uploadCount: Int32(upload.uploads.count))
            }
        }
    }
}
