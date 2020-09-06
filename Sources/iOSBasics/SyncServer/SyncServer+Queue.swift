import Foundation
import SQLite
import ServerShared
import iOSShared

enum SyncServerError: Error {
    case declarationDifferentThanSyncedObject(String)
    case tooManyObjects
    case noObject
    case uploadNotInDeclaredFiles
    case uploadsDoNotHaveDistinctUUIDs
    case declaredFilesDoNotHaveDistinctUUIDs
    case noUploads
    case noDeclaredFiles
    case internalError(String)
    
    static func ==(lhs: Self, rhs: Self) -> Bool {
        switch lhs {
        case declarationDifferentThanSyncedObject:
            guard case .declarationDifferentThanSyncedObject = rhs else {
                return false
            }
            return true
            
        case tooManyObjects:
            guard case .tooManyObjects = rhs else {
                return false
            }
            return true
            
        case noObject:
            guard case .noObject = rhs else {
                return false
            }
            return true
            
        case uploadNotInDeclaredFiles:
            guard case .uploadNotInDeclaredFiles = rhs else {
                return false
            }
            return true
            
        case uploadsDoNotHaveDistinctUUIDs:
            guard case .uploadsDoNotHaveDistinctUUIDs = rhs else {
                return false
            }
            return true
            
        case declaredFilesDoNotHaveDistinctUUIDs:
            guard case .declaredFilesDoNotHaveDistinctUUIDs = rhs else {
                return false
            }
            return true
            
        case noUploads:
            guard case .noUploads = rhs else {
                return false
            }
            return true
            
        case noDeclaredFiles:
            guard case .noDeclaredFiles = rhs else {
                return false
            }
            return true
            
        case internalError(let str1):
            guard case .internalError(let str2) = rhs, str1 == str2 else {
                return false
            }
            return true
        }
    }
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
        let newFiles: Bool
        
        switch declaredObjects.count {
        case 0:
            newFiles = true
            
            // Need to create DeclaredObjectModel
            let declaredObject = try DeclaredObjectModel(db: db, fileGroupUUID: declaration.fileGroupUUID, objectType: declaration.objectType, sharingGroupUUID: declaration.sharingGroupUUID)
            try declaredObject.insert()
                        
            // Need to add entries for the file declarations.
            for file in declaration.declaredFiles {
                let declared = try DeclaredFileModel(db: db, fileGroupUUID: declaration.fileGroupUUID, uuid: file.uuid, mimeType: file.mimeType, cloudStorageType: file.cloudStorageType, appMetaData: file.appMetaData, changeResolverName: file.changeResolverName)
                try declared.insert()
            }
            
            // And, add a DirectoryEntry per file
            for file in declaration.declaredFiles {
                let dirEntry = try DirectoryEntry(db: db, fileUUID: file.uuid, fileVersion: 0, deletedLocally: false, deletedOnServer: false, goneReason: nil)
                try dirEntry.insert()
            }
            
        case 1:
            newFiles = true

            // Already have registered the SyncedObject
            // Need to compare this one against the one in the database.

            let declaredObject = declaredObjects[0]
            guard declaredObject.compare(to: declaration) else {
                throw SyncServerError.declarationDifferentThanSyncedObject("Declared object differs from given one.")
            }
            
            let declaredFilesInDatabase = try DeclaredFileModel.fetch(db: db, where: declaration.fileGroupUUID == DeclaredFileModel.fileGroupUUIDField.description)
            
            let first = Set<DeclaredFileModel>(declaredFilesInDatabase)

            guard DeclaredFileModel.compare(first: first, second: declaration.declaredFiles) else {
                throw SyncServerError.declarationDifferentThanSyncedObject("Declared file model differs from a given one.")
            }
            
            // Check that there is one DirectoryEntry per file
            for file in declaredFilesInDatabase {
                let rows = try DirectoryEntry.fetch(db: db, where: file.uuid == DirectoryEntry.fileUUIDField.description)
                guard rows.count == 1 else {
                    throw SyncServerError.declarationDifferentThanSyncedObject(
                        "DirectoryEntry missing.")
                }
            }

        default:
            throw SyncServerError.internalError("Had two registered DeclaredObject's for the same fileGroupUUID: fileGroupUUID: \(declaration.fileGroupUUID)")
        }
        
        // If there is a UploadObjectTracker, this upload will be deferred. If there is not one, we'll trigger the upload now.
        let objectTrackers = try UploadObjectTracker.fetch(db: db, where: declaration.fileGroupUUID == UploadObjectTracker.fileGroupUUIDField.description)
        
        let existingObjectTrackers = objectTrackers.count > 0
        
        // Add a new tracker into UploadObjectTracker, and one for each new upload.
        let newObjectTracker = try UploadObjectTracker(db: db, fileGroupUUID: declaration.fileGroupUUID)
        try newObjectTracker.insert()
        
        guard let newObjectTrackerId = newObjectTracker.id else {
            throw SyncServerError.internalError("No object tracker id")
        }
        
        for file in uploads {
            let url: URL
            if file.persistence.isCopy {
                url = try FileUtils.copyFileToNewTemporary(original: file.url, config: configuration.temporaryFiles)
            }
            else {
                url = file.url
            }
            
            let declaredFile = try fileDeclaration(for: file.uuid, declaration: declaration)
            let checkSum = try hashingManager.hashFor(cloudStorageType: declaredFile.cloudStorageType).hash(forURL: url)
            
            let fileTracker = try UploadFileTracker(db: db, uploadObjectTrackerId: newObjectTrackerId, status: .notStarted, fileUUID: file.uuid, fileVersion: nil, localURL: url, goneReason: nil, uploadCopy: file.persistence.isCopy, checkSum: checkSum)
            try fileTracker.insert()
        }

        guard !existingObjectTrackers else {
            delegate?.uploadQueued(self, declObjectId: declaration.declObjectId)
            return
        }
        
        let uploadCount = Int32(uploads.count)
        
        for (uploadIndex, file) in uploads.enumerated() {
            let declaredFile = try fileDeclaration(for: file.uuid, declaration: declaration)
            guard let uploadFileTracker = try UploadFileTracker.fetchSingleRow(db: db, where: file.uuid == UploadFileTracker.fileUUIDField.description),
                let checkSum = uploadFileTracker.checkSum,
                let localURL = uploadFileTracker.localURL else {
                throw SyncServerError.internalError("Could not get upload file tracker: \(file.uuid)")
            }
            
            let uploadObjectTrackerId = uploadFileTracker.uploadObjectTrackerId

            let fileVersion:ServerAPI.File.Version
            if newFiles {
                var appMetaData: AppMetaData?
                if let appMetaDataContents = declaredFile.appMetaData {
                    appMetaData = AppMetaData(contents: appMetaDataContents)
                }
                
                fileVersion = .v0(source: .url(localURL), mimeType: declaredFile.mimeType, checkSum: checkSum, changeResolverName: declaredFile.changeResolverName, fileGroupUUID: declaration.fileGroupUUID.uuidString, appMetaData: appMetaData)
            }
            else {
                let data = try Data(contentsOf: localURL)
                fileVersion = .vN(change: data)
            }
            
            let serverAPIFile = ServerAPI.File(fileUUID: file.uuid.uuidString, sharingGroupUUID: declaration.sharingGroupUUID.uuidString, deviceUUID: configuration.deviceUUID.uuidString, uploadObjectTrackerId: uploadObjectTrackerId, version: fileVersion)
            
            if let error = api.uploadFile(file: serverAPIFile, uploadIndex: Int32(uploadIndex + 1), uploadCount: uploadCount) {
                throw SyncServerError.internalError("\(error)")
            }

            try uploadFileTracker.update(setters:
                UploadFileTracker.statusField.description <- .uploading)
        }
        
        // No existing trackers for this object prior to this `queue` call-- need to trigger these uploads.
        
        // See if there are queued object(s) for this file group.
//        let queuedFiles = try UploadFileTracker.numberRows(db: db, where:
//            declaration.fileGroupUUID == UploadFileTracker.fileGroupUUIDField.description
//        )
        
        // Queue tracker(s) for this upload
        var trackers = [UploadFileTracker]()
//        for file in object.files {
//            // TODO: If we get a failure here, we ought to clean up.
//            let tracker = try queueFileUpload(file, forObject: object)
//            trackers += [tracker]
//        }

//        if queuedFiles == 0 {
//            // We can start these uploads.
//            //api.uploadFile(file: <#T##ServerAPI.File#>, serverMasterVersion: <#T##MasterVersionInt#>)
//        }
//        else {
//            // These uploads need to wait.
//        }
    }
    
    private func fileDeclaration<DECL: DeclarableObject>(for uuid: UUID, declaration: DECL) throws -> some DeclarableFile {
        let declaredFiles = declaration.declaredFiles.filter {$0.uuid == uuid}
        guard declaredFiles.count == 1,
            let declaredFile = declaredFiles.first else {
            throw SyncServerError.internalError("Not just one declared file: \(declaredFiles.count)")
        }
        
        return declaredFile
    }
}
