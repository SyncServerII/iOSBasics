
import Foundation
import SQLite
import iOSShared

extension SyncServer {
    // Only re-check of uploads so far. This handles vN uploads only. v0 uploads are always handled in `queueObject`.
    func triggerUploads() throws {
        try triggerRetryFileUploads()
        
        let notStartedUploads = try UploadObjectTracker.allUploadsWith(status: .notStarted, db: db)
        guard notStartedUploads.count > 0 else {
            return
        }
        
        // What uploads are currently in-progress? i.e., what objects have any file trackers with a status of .uploading?        
        let inProgress = try UploadObjectTracker.anyUploadsWith(status: .uploading, db: db)
        let fileGroupsInProgress = Set<UUID>(inProgress.map { $0.object.fileGroupUUID })
        
        // These are the objects we want to `exclude` from uploading. Start off with the file groups actively uploading. Don't want parallel uploads for the same file group.
        var currentObjects = fileGroupsInProgress
        
        var toTrigger = [UploadObjectTracker.UploadWithStatus]()
        
        for upload in notStartedUploads {
            // Don't want parallel uploads for the same declared object.
            guard !currentObjects.contains(upload.object.fileGroupUUID) else {
                continue
            }
            
            currentObjects.insert(upload.object.fileGroupUUID)
            toTrigger += [upload]
        }
        
        guard toTrigger.count > 0 else {
            return
        }
        
        // Now can actually trigger the uploads.
        
        for uploadObject in toTrigger {
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
    }

    // See if individual files need re-triggering. These will be for uploads that failed and need retrying.
    private func triggerRetryFileUploads() throws {
        var filesToTrigger = [UploadFileTracker]()
        
        // We want to check objects that are currently in progress, uploading, and see if any of their files are .notStarted
        let inProgressObjects = try UploadObjectTracker.allUploadsWith(status: .uploading, db: db)
        for object in inProgressObjects {
            let toTrigger = object.files.filter {$0.status == .notStarted}
            filesToTrigger += toTrigger
        }
                
        for fileTracker in filesToTrigger {
            guard let objectTracker = try UploadObjectTracker.fetchSingleRow(db: db, where: UploadObjectTracker.idField.description == fileTracker.uploadObjectTrackerId) else {
                throw SyncServerError.internalError("Could not get UploadObjectTracker")
            }
            
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
}
