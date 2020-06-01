import Foundation
import SQLite
import ServerShared

extension SyncServer {
    func queueObject(_ object: SyncedObject) throws {
        // See if there are queued object(s) for this file group.
        let queuedFiles = try UploadFileTracker.numberRows(db: database, where:
            object.fileGroupUUID == UploadFileTracker.fileGroupUUIDField.description
        )
        
        // Queue tracker(s) for this upload
        var trackers = [UploadFileTracker]()
        for file in object.files {
            // TODO: If we get a failure here, we ought to clean up.
            let tracker = try queueFileUpload(file, forObject: object)
            trackers += [tracker]
        }

        if queuedFiles == 0 {
            // We can start these uploads.
            //api.uploadFile(file: <#T##ServerAPI.File#>, serverMasterVersion: <#T##MasterVersionInt#>)
        }
        else {
            // These uploads need to wait.
        }
    }
    
    private func queueFileUpload(_ file: File, forObject object: SyncedObject) throws -> UploadFileTracker {
        var entry:DirectoryEntry! = try DirectoryEntry.fetchSingleRow(db: database, where:
            file.uuid == UploadFileTracker.fileUUIDField.description)
        let cloudStorageType: CloudStorageType
        
        if entry == nil {
            // This is a new file.
            cloudStorageType = try signIns.cloudStorageTypeForNewFile(db: database, sharingGroupUUID: object.sharingGroup)
            entry = try DirectoryEntry(db: database, fileUUID: file.uuid, mimeType: file.mimeType, fileVersion: 0, sharingGroupUUID: object.sharingGroup, cloudStorageType: cloudStorageType, deletedLocally: false, deletedOnServer: false, appMetaData: file.appMetaData, appMetaDataVersion: 0, fileGroupUUID: object.fileGroupUUID, goneReason: nil)
            try entry?.insert()
        }
        else {
            // Existing file.
            cloudStorageType = entry.cloudStorageType
        }
        
        let hasher = try hashingManager.hashFor(cloudStorageType: cloudStorageType)
        let checkSum = try hasher.hash(forURL: file.url)
        
        let uploadTracker = try UploadFileTracker(db: database, status: .notStarted, sharingGroupUUID: object.sharingGroup, appMetaData: file.appMetaData, appMetaDataVersion: nil, fileGroupUUID: object.fileGroupUUID, fileUUID: file.uuid, fileVersion: nil, localURL: file.url, mimeType: file.mimeType, goneReason: nil, uploadCopy: file.persistence.isCopy, uploadUndeletion: false, checkSum: checkSum)
        try uploadTracker.insert()
        
        return uploadTracker
    }
}
