import Foundation
import SQLite
import ServerShared
import iOSShared

enum SyncServerError: Error {
    case declarationDifferentThanSyncedObject
    case tooManyObjects
    case noObject
    case uploadNotInDeclaredFiles
    case uploadsDoNotHaveDistinctUUIDs
    case declaredFilesDoNotHaveDistinctUUIDs
    case noUploads
    case noDeclaredFiles
}

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
            
        switch declaredObjects.count {
        case 0:
            // Need to create DeclaredObjectModel
            let declaredObject = try DeclaredObjectModel(db: db, fileGroupUUID: declaration.fileGroupUUID, objectType: declaration.objectType, sharingGroupUUID: declaration.sharingGroupUUID)
            try declaredObject.insert()
                        
            // Need to add entries for the file declarations.
            for file in declaration.declaredFiles {
                let declared = try DeclaredFileModel(db: db, fileGroupUUID: declaration.fileGroupUUID, uuid: file.uuid, mimeType: file.mimeType, appMetaData: file.appMetaData, changeResolverName: file.changeResolverName)
                try declared.insert()
            }

        case 1:
            // Already have registered the SyncedObject
            // Need to compare this one against the one in the database.

            let declaredObject = declaredObjects[0]
            guard declaredObject.compare(to: declaration) else {
                throw SyncServerError.declarationDifferentThanSyncedObject
            }
            
            let declaredFilesInDatabase = try DeclaredFileModel.fetch(db: db, where: declaration.fileGroupUUID == DeclaredFileModel.fileGroupUUIDField.description)
            
            let first = Set<DeclaredFileModel>(declaredFilesInDatabase)

            guard DeclaredFileModel.compare(first: first, second: declaration.declaredFiles) else {
                throw SyncServerError.declarationDifferentThanSyncedObject
            }

        default:
            logger.error("Had two registered DeclaredObject's for the same fileGroupUUID: fileGroupUUID: \(declaration.fileGroupUUID)")
        }
        
        // See if there are queued object(s) for this file group.
        let queuedFiles = try UploadFileTracker.numberRows(db: db, where:
            declaration.fileGroupUUID == UploadFileTracker.fileGroupUUIDField.description
        )
        
        // Queue tracker(s) for this upload
        var trackers = [UploadFileTracker]()
//        for file in object.files {
//            // TODO: If we get a failure here, we ought to clean up.
//            let tracker = try queueFileUpload(file, forObject: object)
//            trackers += [tracker]
//        }

        if queuedFiles == 0 {
            // We can start these uploads.
            //api.uploadFile(file: <#T##ServerAPI.File#>, serverMasterVersion: <#T##MasterVersionInt#>)
        }
        else {
            // These uploads need to wait.
        }
    }
    
    private func queueFileUpload<FILE: UploadableFile>(_ file: FILE, syncObjectId: UUID) throws -> UploadFileTracker {
        var entry:DirectoryEntry! = try DirectoryEntry.fetchSingleRow(db: db, where:
            file.uuid == UploadFileTracker.fileUUIDField.description)
        var cloudStorageType: CloudStorageType!
        
        if entry == nil {
            // This is a new file.
//            cloudStorageType = try signIns.cloudStorageTypeForNewFile(db: database, sharingGroupUUID: object.sharingGroup)
//            entry = try DirectoryEntry(db: database, fileUUID: file.uuid, mimeType: file.mimeType, fileVersion: 0, sharingGroupUUID: object.sharingGroup, cloudStorageType: cloudStorageType, deletedLocally: false, deletedOnServer: false, appMetaData: file.appMetaData, appMetaDataVersion: 0, fileGroupUUID: object.fileGroupUUID, goneReason: nil)
//            try entry?.insert()
        }
        else {
            // Existing file.
            cloudStorageType = entry.cloudStorageType
        }
        
        let hasher = try hashingManager.hashFor(cloudStorageType: cloudStorageType)
        let checkSum = try hasher.hash(forURL: file.url)
        var uploadTracker:UploadFileTracker!
//        let uploadTracker = try UploadFileTracker(db: database, status: .notStarted, sharingGroupUUID: object.sharingGroup, appMetaData: file.appMetaData, fileGroupUUID: object.fileGroupUUID, fileUUID: file.uuid, fileVersion: nil, localURL: file.url, mimeType: file.mimeType, goneReason: nil, uploadCopy: file.persistence.isCopy, uploadUndeletion: false, checkSum: checkSum)
//        try uploadTracker.insert()
//
//        return uploadTracker
        assert(false)
        return uploadTracker
    }
}
