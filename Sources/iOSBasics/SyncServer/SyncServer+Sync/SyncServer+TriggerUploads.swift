
import Foundation
import SQLite

extension SyncServer {
/*
    // Only re-check of uploads so far. This handles vN uploads only. v0 uploads are always handled in `queueObject`.
    func triggerUploads() throws {
        let notStartedUploads = try UploadObjectTracker.allUploadsWith(status: .notStarted, db: db)
        guard notStartedUploads.count > 0 else {
            return
        }
        
        // What uploads are currently in-progress?
        let inProgress = try UploadObjectTracker.allUploadsWith(status: .uploading, db: db)
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
            let uploadCount = Int32(uploadObject.files.count)
            let declaredObject:ObjectDeclaration = try DeclaredObjectModel.lookupDeclarableObject(fileGroupUUID: uploadObject.object.fileGroupUUID, db: db)
            
            guard let objectId = uploadObject.object.id else {
                throw SyncServerError.internalError("Could not get object id")
            }
            
            let fileUUIDs = uploadObject.files.map { $0.fileUUID }
            guard let versions = try DirectoryEntry.versionOfAllFiles(fileUUIDs: fileUUIDs, db: db) else {
                throw SyncServerError.attemptToQueueUploadOfVNAndV0Files
            }
            
            let v0Upload = versions == .v0
            try uploadObject.object.update(setters:
                UploadObjectTracker.v0UploadField.description <- v0Upload)
            
            for (uploadIndex, file) in uploadObject.files.enumerated() {
                try singleUpload(declaration: declaredObject, fileUUID: file.fileUUID, v0Upload: v0Upload, objectTrackerId: objectId, uploadIndex: Int32(uploadIndex + 1), uploadCount: uploadCount)
            }
        }
    }
    */
}
