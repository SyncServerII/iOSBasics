
import Foundation
import SQLite
import iOSShared
import ServerShared

extension SyncServer {
    enum UploadRetryError: Error {
        case noV0Upload
    }
    
    func triggerUploads() throws {
        // Retry file uploads that haven't completed, but that have exceeded their expiry duration.
        try triggerRetryOfExpiredFileUploads()
        
        // Retry any upload objects that are still .uploading, but that have files that are not yet started.
        try triggerRetryFileUploads()
        
        // Trigger other upload objects that are .notStarted -- these will either be completely new uploads or uploads that were already tried before.
        try triggerQueuedUploads()
    }

    // See if individual files need re-triggering because their expiry date was exceeded. We have found specifically that we can fail to get positive results of the server succeeding on uploads in some cases, and the files remain in an `.uploading` state. See https://github.com/SyncServerII/Neebla/issues/25#issuecomment-894711039
    private func triggerRetryOfExpiredFileUploads() throws {
        let expiredUploadTrackers = try UploadFileTracker.fetch(db: db, where: UploadFileTracker.statusField.description == .uploading).filter {
            try $0.hasExpired()
        }
        
        guard expiredUploadTrackers.count > 0 else {
            return
        }
        
        let backgroundCache = BackgroundCache(database: db)
        
        // Restarting v0 uploads is fairly straightforward. However, restarting vN uploads is not so simple.
        // Partition the upload trackers by their uploading object to assess v0 vs. vN.
        
        let partitionedUploadTrackers = Partition.array(expiredUploadTrackers, using: \.uploadObjectTrackerId)
        for uploadsForSingleObject in partitionedUploadTrackers {
            // This shouldn't happen. But just be safe.
            guard uploadsForSingleObject.count > 0 else {
                continue
            }
            
            let firstFileTracker = uploadsForSingleObject[0]
            
            guard let uploadObject = try UploadObjectTracker.fetchSingleRow(db: db, where: UploadObjectTracker.idField.description == firstFileTracker.uploadObjectTrackerId) else {
                throw DatabaseError.notExactlyOneRow
            }
            
            guard let v0Upload = uploadObject.v0Upload else {
                throw UploadRetryError.noV0Upload
            }
            
            if v0Upload {
                try retryExpiredUploads(uploadsForSingleObject: uploadsForSingleObject, object: uploadObject, backgroundCache: backgroundCache)
            }
            else {
                // Check with the server to see if these have actually completed. We're trying to deal with the possibility that the server actually completed all of these uploads (but the results didn't get back to the client). vN uploads are more complicated because if they've all completed, an upload retry won't simply respond with success -- at the point we try to use the same batchUUID in the DeferredUpload table.
                checkExpiredVNFileUploads(uploadsForSingleObject: uploadsForSingleObject, object: uploadObject, backgroundCache: backgroundCache)
            }
        }
    }
    
    func retryExpiredUploads(uploadsForSingleObject: [UploadFileTracker], object: UploadObjectTracker, backgroundCache: BackgroundCache) throws {
        for expiredUpload in uploadsForSingleObject {                    
            try retryFileUpload(fileTracker: expiredUpload, objectTracker: object)
        }
    }
    
    // Trigger new uploads for file groups where those have been queued before, but not started (or started and failed). This handles v0 and vN uploads. v0 uploads will be triggered here if they failed in their initial upload from `queue(upload: UploadableObject)` (or if multiple v0 uploads occur for a given file group).
    // Doesn't trigger more if at least `maxConcurrentFileGroupUploads` objects have uploading files.
    private func triggerQueuedUploads() throws {
        var toTrigger = try UploadObjectTracker.toBeStartedNext(db: db)

        logger.info("triggerQueuedUploads: toTrigger.count: \(toTrigger.count)")
        guard toTrigger.count > 0 else {
            return
        }
        
        let number = try UploadObjectTracker.numberFileGroupsUploading(db: db)
        if number >= configuration.maxConcurrentFileGroupUploads {
            return
        }
        
        let additional = configuration.maxConcurrentFileGroupUploads - number
        toTrigger = Array<UploadObjectTracker.UploadWithStatus>(toTrigger.prefix(additional))
                
        for uploadObject in toTrigger {
            try triggerUploads(uploadObject: uploadObject)
        }
    }

    private func triggerUploads(uploadObject: UploadObjectTracker.UploadWithStatus) throws {
        for file in uploadObject.files {
            try retryFileUpload(fileTracker: file, objectTracker: uploadObject.object)
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
