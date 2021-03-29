
import Foundation
import SQLite
import iOSShared

extension SyncServer {
    func triggerUploads() throws {
        // Retry any upload objects that are still .uploading, but that have files that are not yet started.
        try triggerRetryFileUploads()
        
        // Trigger other upload objects that are .notStarted -- these will either be completely new uploads or uploads that were already tried before.
        try triggerQueuedUploads()
    }
    
    // Trigger new uploads for file groups where those have been queued before, but not started (or started and failed). This handles v0 and vN uploads. v0 uploads will be triggered here if they failed in their initial upload from `queue(upload: UploadableObject)` (or if multiple v0 uploads occur for a given file group).
    private func triggerQueuedUploads() throws {
        let toTrigger = try UploadObjectTracker.toBeStartedNext(db: db)

        logger.info("triggerQueuedUploads: toTrigger.count: \(toTrigger.count)")
        guard toTrigger.count > 0 else {
            return
        }
        
        // Trigger the uploads.
        
        for uploadObject in toTrigger {
            let newUploads = uploadObject.files.filter {$0.uploadIndex == nil || $0.uploadCount == nil}
            
            // Should be all or none
            
            if newUploads.count == 0 {
                logger.info("triggerQueuedUploads: newUploads.count: \(newUploads.count)")
                try triggerExistingUploads(uploadObject: uploadObject)
            }
            else if newUploads.count == newUploads.count {
                logger.info("triggerQueuedUploads: newUploads.count: \(newUploads.count)")
                try triggerNewUploads(uploadObject: uploadObject)
            }
            else {
                throw SyncServerError.internalError("newUploads.count == 0 || newUploads.files.count == newUploads.count failed")
            }
        }
    }
    
    private func triggerExistingUploads(uploadObject: UploadObjectTracker.UploadWithStatus) throws {
        for file in uploadObject.files {
            try retryFileUpload(fileTracker: file, objectTracker: uploadObject.object)
        }
    }
    
    private func triggerNewUploads(uploadObject: UploadObjectTracker.UploadWithStatus) throws {
        guard let objectEntry = try DirectoryObjectEntry.fetchSingleRow(db: db, where: DirectoryObjectEntry.fileGroupUUIDField.description == uploadObject.object.fileGroupUUID) else {
            throw SyncServerError.internalError("Could not get DirectoryObjectEntry")
        }
        
        let uploadCount = Int32(uploadObject.files.count)
        guard let declaredObject = try DeclaredObjectModel.fetchSingleRow(db: db, where: DeclaredObjectModel.objectTypeField.description == objectEntry.objectType) else {
            throw SyncServerError.internalError("Could not get DeclaredObjectModel")
        }
        
        let fileUUIDs = uploadObject.files.map { $0.fileUUID }
        guard let versions = try DirectoryFileEntry.versionOfAllFiles(fileUUIDs: fileUUIDs, db: db) else {
            throw SyncServerError.attemptToQueueUploadOfVNAndV0Files
        }
        
        let v0Upload = versions == .v0
        uploadObject.object.v0Upload = v0Upload
        try uploadObject.object.update(setters:
            UploadObjectTracker.v0UploadField.description <- v0Upload)
        
        for (uploadIndex, file) in uploadObject.files.enumerated() {
            guard let fileEntry = try DirectoryFileEntry.fetchSingleRow(db: db, where: DirectoryFileEntry.fileUUIDField.description == file.fileUUID) else {
                throw SyncServerError.internalError("Could not get DirectoryFileEntry")
            }
            
            try singleUpload(objectType: declaredObject, objectTracker: uploadObject.object, objectEntry: objectEntry, fileLabel: fileEntry.fileLabel, fileUUID: file.fileUUID, uploadIndex: Int32(uploadIndex + 1), uploadCount: uploadCount)
        }
    }
    
    // See if individual files need re-triggering. These will be for uploads that failed and need retrying.
    private func triggerRetryFileUploads() throws {
        var filesToTrigger = [UploadFileTracker]()
        
        // We want to check objects that are currently .uploading, and see if any of their files are .notStarted
        let inProgressObjects = try UploadObjectTracker.uploadsMatching(filePredicate:{$0.status == .uploading}, scope: .any, db: db)
        
        for object in inProgressObjects {
            let toTrigger = object.files.filter {$0.status == .notStarted}
            filesToTrigger += toTrigger
        }
                
        for fileTracker in filesToTrigger {
            guard let objectTracker = try UploadObjectTracker.fetchSingleRow(db: db, where: UploadObjectTracker.idField.description == fileTracker.uploadObjectTrackerId) else {
                throw SyncServerError.internalError("Could not get UploadObjectTracker")
            }
            
            try retryFileUpload(fileTracker: fileTracker, objectTracker: objectTracker)
        }
    }
    
    private func retryFileUpload(fileTracker: UploadFileTracker, objectTracker: UploadObjectTracker) throws {
        guard let objectEntry = try DirectoryObjectEntry.fetchSingleRow(db: db, where: DirectoryObjectEntry.fileGroupUUIDField.description == objectTracker.fileGroupUUID) else {
            throw SyncServerError.internalError("Could not get DirectoryObjectEntry")
        }
        
        guard let fileEntry = try DirectoryFileEntry.fetchSingleRow(db: db, where: DirectoryFileEntry.fileUUIDField.description == fileTracker.fileUUID) else {
            throw SyncServerError.internalError("Could not get DirectoryFileEntry")
        }

        guard let declaredObject = try DeclaredObjectModel.fetchSingleRow(db: db, where: DeclaredObjectModel.objectTypeField.description == objectEntry.objectType) else {
            throw SyncServerError.internalError("Could not get DeclaredObjectModel")
        }
        
        try uploadSingle(objectType: declaredObject, objectTracker: objectTracker, objectEntry: objectEntry, fileTracker: fileTracker, fileLabel: fileEntry.fileLabel)
        
        logger.debug("Retrying upload for file: \(fileTracker.fileUUID)")
    }
}
