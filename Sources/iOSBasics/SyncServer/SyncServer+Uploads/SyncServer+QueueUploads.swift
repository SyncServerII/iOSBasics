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
    private func directoryEntryMatchingFileLabelUUID(of upload: UploadableFile, in fileEntries:[DirectoryFileEntry]) throws -> DirectoryFileEntry? {
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
            let fileEntry = try directoryEntryMatchingFileLabelUUID(of: upload, in: objectInfo.allFileEntries)
            if fileEntry == nil {
                // The fileLabel/UUID has not yet been uploaded.
                v0Uploads += [upload]
            }
        }
        
        return v0Uploads
    }
    
    // Given that all files in the upload have been uploaded before, make sure that either (a) the mimeType in the UploadableFile is nil, and the declared object has exactly one mimeType, or (b) the mimeType in the UploadableFile is non-nil and that matches with the mime type in the existing DirectoryFileEntry.
    private func existingUploadsHaveSameMimeType(upload: UploadableObject, objectModel: DeclaredObjectModel, objectInfo: DirectoryObjectEntry.ObjectInfo) throws {
                
        for upload in upload.uploads {
            guard let fileEntry:DirectoryFileEntry = try directoryEntryMatchingFileLabelUUID(of: upload, in: objectInfo.allFileEntries) else {
                throw SyncServerError.internalError("Should have a matching directory entry.")
            }

            if let mimeType = upload.mimeType {
                guard fileEntry.mimeType == mimeType else {
                    throw SyncServerError.attemptToUploadWithDifferentMimeType
                }
            }
            else {
                let fileDeclaration = try objectModel.getFile(with: upload.fileLabel)
                guard fileDeclaration.mimeTypes.count == 1 else {
                    throw SyncServerError.nilUploadMimeTypeButNotJustOneMimeTypeInDeclaration
                }
            }
        }
    }
    
    private func newUploadsHaveValidMimeType(upload: UploadableObject, objectModel: DeclaredObjectModel) throws {

        for upload in upload.uploads {
            let fileDeclaration = try objectModel.getFile(with: upload.fileLabel)

            if let mimeType = upload.mimeType {
                guard fileDeclaration.mimeTypes.contains(mimeType) else {
                    throw SyncServerError.mimeTypeNotInDeclaration
                }
            }
            else {
                // Nil mime type given-- make sure there's just one mime type in the declaration.
                guard fileDeclaration.mimeTypes.count == 1 else {
                    throw SyncServerError.nilUploadMimeTypeButNotJustOneMimeTypeInDeclaration
                }
            }
        }
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
            
            // If there is an active upload for this fileGroupUUID, then this upload will be locally queued for later processing.
            // Additionally, want to see if there are any .notStarted v0 uploads. That will take priority over this new upload because v0 uploads take priority. (This can happen if, for example, a v0 upload didn't happen because it failed.)
            
            let activeUploads =
                try UploadObjectTracker.uploadsMatching(
                    filePredicate: {$0.status == .uploading},
                    scope: .any,
                    whereObjects:
                        UploadObjectTracker.fileGroupUUIDField.description == objectInfo.objectEntry.fileGroupUUID, db: db)
             let pendingV0Uploads =
                try UploadObjectTracker.uploadsMatching(
                    filePredicate: {$0.status == .notStarted},
                    scope: .any,
                    whereObjects:
                        UploadObjectTracker.fileGroupUUIDField.description == objectInfo.objectEntry.fileGroupUUID, db: db)
                    .filter { $0.object.v0Upload == true }
                        
            let activeUploadsForThisFileGroup = activeUploads.count > 0 || pendingV0Uploads.count > 0

            // All files must be either v0 or vN
            if v0Uploads.count == 0 {
                // vN uploads
                try uploadExisting(upload: upload, objectModel: declaredObject, objectEntry: objectInfo, activeUploadsForThisFileGroup: activeUploadsForThisFileGroup)
            }
            else if v0Uploads.count == upload.uploads.count {
                // v0 uploads
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
    }
    
    // Add a new tracker into UploadObjectTracker, and one for each new upload.
    // Also assigns uploadCount and uploadIndex to each UploadObjectTracker.
    private func createNewTrackers(fileGroupUUID: UUID, pushNotificationMessage:String?, objectModel: DeclaredObjectModel, cloudStorageType: CloudStorageType, uploads: [UploadableFile]) throws -> (newObjectTrackerId: Int64, UploadObjectTracker) {
    
        let batchUUID = UUID()
            
        let newObjectTracker = try UploadObjectTracker(db: db, fileGroupUUID: fileGroupUUID, batchUUID: batchUUID, batchExpiryInterval: UploadObjectTracker.expiryInterval, pushNotificationMessage: pushNotificationMessage)
        try newObjectTracker.insert()
                
        guard let newObjectTrackerId = newObjectTracker.id else {
            throw SyncServerError.internalError("No object tracker id")
        }
        
        logger.debug("newObjectTrackerId: \(newObjectTrackerId)")
        
        let uploadCount:Int32 = Int32(uploads.count)
        
        // Create a new `UploadFileTracker` for each file we're uploading.
        for (uploadIndex, file) in uploads.enumerated() {
            // uploadIndex + 1 because the indices range from 1 to uploadCount
            let newFileTracker = try UploadFileTracker.create(file: file, objectModel: objectModel, cloudStorageType: cloudStorageType, objectTrackerId: newObjectTrackerId, uploadIndex: Int32(uploadIndex + 1), uploadCount: uploadCount, config: configuration.temporaryFiles, hashingManager: hashingManager, db: db)
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
        
        // Need to look up directory entries for each file and make sure for each the mime type we're uploading now is the same as the mime type that was uploaded before.
        try existingUploadsHaveSameMimeType(upload: upload, objectModel: objectModel, objectInfo: objectEntry)
        
        // Every new upload needs new upload trackers.
        let (_, newObjectTracker) = try createNewTrackers(fileGroupUUID: upload.fileGroupUUID, pushNotificationMessage: upload.pushNotificationMessage, objectModel: objectModel, cloudStorageType: objectEntry.objectEntry.cloudStorageType, uploads: upload.uploads)
        
        // This is an upload for existing file instances.
        newObjectTracker.v0Upload = false
        try newObjectTracker.update(setters: UploadObjectTracker.v0UploadField.description <- newObjectTracker.v0Upload)
                
        if activeUploadsForThisFileGroup || !requestable.canMakeNetworkRequests {
            delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.uploadQueue(self, event: .queued(fileGroupUUID: upload.fileGroupUUID))
            }
        } else {
            for uploadFile in upload.uploads {
                try singleUpload(objectType: objectModel, objectTracker: newObjectTracker, objectEntry: objectEntry.objectEntry, fileLabel: uploadFile.fileLabel, fileUUID: uploadFile.uuid)
            }
        }
    }
    
    // This is either the first upload for the file group. i.e., the first upload for this specific object. OR, it's the first upload for only some of the files in the file group.
    private func uploadNew(upload: UploadableObject, objectType: DeclaredObjectModel, objectEntryType: DirectoryObjectEntry.ObjectEntryType, activeUploadsForThisFileGroup: Bool) throws {

        // Make sure all of the mime types in the upload match those needed.
        try newUploadsHaveValidMimeType(upload: upload, objectModel: objectType)
        
        // The user must do at least one `sync` call prior to queuing an upload or this may throw an error.
        let cloudStorageType = try cloudStorageTypeForNewFile(sharingGroupUUID: upload.sharingGroupUUID)
        
        // Need directory entries for this new specific object instance.
        let objectEntry = try DirectoryObjectEntry.createNewInstance(upload: upload, objectType: objectType, objectEntryType: objectEntryType, cloudStorageType: cloudStorageType, db: db)

        // Every new upload needs new upload trackers.
        let (_, newObjectTracker) = try createNewTrackers(fileGroupUUID: upload.fileGroupUUID, pushNotificationMessage: upload.pushNotificationMessage, objectModel: objectType, cloudStorageType: cloudStorageType, uploads: upload.uploads)
        
        // Since this is the first upload for a new object instance or at least for the specific files of the object, all uploads are v0.
        newObjectTracker.v0Upload = true
        try newObjectTracker.update(setters: UploadObjectTracker.v0UploadField.description <- newObjectTracker.v0Upload)
        
        if activeUploadsForThisFileGroup || !requestable.canMakeNetworkRequests {
            delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.uploadQueue(self, event: .queued(fileGroupUUID: upload.fileGroupUUID))
            }
        }
        else {
            for uploadFile in upload.uploads {
                try singleUpload(objectType: objectType, objectTracker: newObjectTracker, objectEntry: objectEntry, fileLabel: uploadFile.fileLabel, fileUUID: uploadFile.uuid)
            }
        }
    }
}
