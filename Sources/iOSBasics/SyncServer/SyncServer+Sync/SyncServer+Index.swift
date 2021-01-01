
import Foundation
import SQLite
import ServerShared
import iOSShared

extension SyncServer {
    // Operates asynchronously.
    func getIndex(sharingGroupUUID: UUID?) {
        api.index(sharingGroupUUID: sharingGroupUUID) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let indexResult):
                do {
                    try self.upsert(sharingGroups: indexResult.sharingGroups)
                } catch {
                    self.delegator { [weak self] delegate in
                        guard let self = self else { return }
                        delegate.userEvent(self, event: .error(error))
                    }
                    return
                }
                
                guard let sharingGroupUUID = sharingGroupUUID else {
                    self.delegator { [weak self] delegate in
                        guard let self = self else { return }
                        delegate.syncCompleted(self, result: .noIndex)
                    }
                    return
                }

                guard let fileIndex = indexResult.fileIndex else {
                    self.delegator { [weak self] delegate in
                        guard let self = self else { return }
                        delegate.userEvent(self, event: .error(SyncServerError.internalError("Nil fileIndex but a sharing group was given.")))                        
                    }
                    return
                }
                
                let indexObjects:[IndexObject]
                
                do {
                    try self.upsert(fileIndex: fileIndex, sharingGroupUUID: sharingGroupUUID)
                    indexObjects = try fileIndex.toIndexObjects()
                } catch {
                    self.delegator { [weak self] delegate in
                        guard let self = self else { return }
                        delegate.userEvent(self, event: .error(error))
                    }
                    return
                }

                self.delegator { [weak self] delegate in
                    guard let self = self else { return }
                    delegate.syncCompleted(self, result: .index(sharingGroupUUID: sharingGroupUUID, index: indexObjects))
                }
                
            case .failure(let error):
                self.delegator { [weak self] delegate in
                    guard let self = self else { return }
                    delegate.userEvent(self, event: .error(error))
                }
            }
        }
    }
    
    // `sharingGroups` is the full set of sharing groups returned from the server.
    private func upsert(sharingGroups: [ServerShared.SharingGroup]) throws {
        // Have any sharing groups been removed?
        let localSharingGroups = Set<UUID>(try SharingEntry.fetch(db: db).map { $0.sharingGroupUUID })
        
        let remoteSharingGroups = Set<UUID>(try sharingGroups.map { group throws -> UUID in
            guard let uuidString = group.sharingGroupUUID,
                let uuid = UUID(uuidString: uuidString) else {
                throw SyncServerError.internalError("Bad UUID")
            }
            return uuid
        })
        
        // I want to know which groups are in the local, but not in the remote. These are the groups that need to be marked as deleted.
        let toDelete = localSharingGroups.subtracting(remoteSharingGroups)
        
        for uuid in toDelete {
            guard let entry = try SharingEntry.fetchSingleRow(db: db, where: SharingEntry.sharingGroupUUIDField.description == uuid) else {
                throw SyncServerError.internalError("Could not get sharing group")
            }
            
            try entry.update(setters: SharingEntry.deletedField.description <- true)
        }
        
        for sharingGroup in sharingGroups {
            try SharingEntry.upsert(sharingGroup: sharingGroup, db: db)
        }
    }
    
    // This has a somewhat similar effect to the preliminary part of doing a `queue` call on the SyncServer interface. It reconstructs the database DirectoryObjectEntry's and DirectoryFileEntry's from the fileIndex. All object type declarations must be done locally and previously within the app.
    // This has no effect if no elements in `fileIndex`.
    // Not private only to enable testing; otherwise, don't call this from outside of this file.
    func upsert(fileIndex: [FileInfo], sharingGroupUUID: UUID) throws {
        guard fileIndex.count > 0 else {
            return
        }
        
        // Each FileInfo must have a fileUUID and each fileUUID must be distinct.
        guard Set<String>(fileIndex.compactMap {$0.fileUUID}).count == fileIndex.count else {
            throw SyncServerError.internalError("fileUUID's were not distinct.")
        }
        
        try checkInvariants(fileIndex: fileIndex, sharingGroupUUID: sharingGroupUUID)
        let fileGroups = Partition.array(fileIndex, using: \.fileGroupUUID)
        
        for fileGroup in fileGroups {
            guard fileGroup.count > 0 else {
                throw SyncServerError.internalError("Not at least one element")
            }
                        
            // All objectTypes across the fileGroup must be either nil, or the same string value
            let objectTypes = Set<String>(fileGroup.compactMap { $0.objectType })
            
            switch objectTypes.count {
            case 0:
                logger.warning("No object type!")
            case 1:
                break
            default:
                throw SyncServerError.internalError("Not one object type")
            }
            
            let firstFile = fileGroup[0]
            
            // All files in fileGroup will have this fileGroupUUID due to partitioning.
            guard let fileGroupUUIDString = firstFile.fileGroupUUID,
                let fileGroupUUID = UUID(uuidString: fileGroupUUIDString) else {
                throw SyncServerError.internalError("Could not get fileGroupUUID field")
            }
            
            let objectType = try helperDelegate.getObjectType(file: firstFile)

            let _ = try DirectoryObjectEntry.matchSert(fileInfo: firstFile, objectType: objectType, db: db)
            
            var deletedCount = 0
            
            for file in fileGroup {
                let (fileEntry, deleted) = try DirectoryFileEntry.upsert(fileInfo: file, objectType: objectType, objectDeclarations: objectDeclarations, db: db)
                if deleted {
                    deletedCount += 1
                    delegator { [weak self] delegate in
                        guard let self = self else { return }
                        delegate.downloadDeletion(self, details: .file(fileEntry.fileUUID))
                    }
                }
            }
            
            guard deletedCount == 0 || deletedCount == fileGroup.count else {
                throw SyncServerError.internalError("Some but not all of file group deleted.")
            }
            
            if deletedCount > 0 {
                delegator { [weak self] delegate in
                    guard let self = self else { return }
                    delegate.downloadDeletion(self, details: .fileGroup(fileGroupUUID))
                }
            }
        }
    }
    
    private func checkInvariants(fileIndex: [FileInfo], sharingGroupUUID: UUID) throws {
        // All files must have the sharingGroupUUID
        let sharingGroups = Set<String>(fileIndex.compactMap {$0.sharingGroupUUID})
        guard sharingGroups.count == 1 else {
            throw SyncServerError.internalError("Not just one sharing group")
        }
        
        guard sharingGroupUUID.uuidString == fileIndex[0].sharingGroupUUID else {
            throw SyncServerError.internalError("sharingGroupUUID didn't match")
        }
        
        for file in fileIndex {
            guard let fileUUIDString = file.fileUUID,
                let fileUUID = UUID(uuidString: fileUUIDString) else {
                throw SyncServerError.internalError("A file UUID string couldn't be converted to a UUID.")
            }
            
            guard let fileGroupUUIDString = file.fileGroupUUID,
                let fileGroupUUID = UUID(uuidString: fileGroupUUIDString) else {
                throw SyncServerError.internalError("A file UUID string couldn't be converted to a UUID.")
            }

            var hasFileEntry = false
            var hasObjectEntry = false

            let objectType = try helperDelegate.getObjectType(file: file)
            
            // We might want to weaken this later, but for initial testing, fail if we don't know about the declared object. One reason to weaken this later is for migration purposes. Some app instance could have been upgraded, but a current one doesn't yet know about a new object type.
            guard let declaredObject = try DeclaredObjectModel.fetchSingleRow(db: db, where: DeclaredObjectModel.objectTypeField.description == objectType) else {
                throw SyncServerError.internalError("No declared object!")
            }
            
            let fileLabel = try file.getFileLabel(objectType: objectType, objectDeclarations: objectDeclarations)

            let fileDeclaration:FileDeclaration = try declaredObject.getFile(with: fileLabel)
            
            guard fileDeclaration == file else {
                throw SyncServerError.internalError("FileDeclaration not the same as FileInfo")
            }
            
            if let fileEntry = try DirectoryFileEntry.fetchSingleRow(db: db, where: DirectoryFileEntry.fileUUIDField.description == fileUUID) {
                
                hasFileEntry = true
                
                guard fileEntry.sameInvariants(fileInfo: file) else {
                    throw SyncServerError.internalError("Invariants of a FileInfo changed.")
                }
            }
            
            if let objectEntry = try DirectoryObjectEntry.fetchSingleRow(db: db, where: DirectoryObjectEntry.fileGroupUUIDField.description == fileGroupUUID) {
                
                hasObjectEntry = true
                
                guard objectEntry == file else {
                    throw SyncServerError.internalError("Invariants of a FileInfo changed.")
                }
            }

            // Two possible cases with an existing declared object: Either this is a new file for the object (i.e., clients don't have to upload all files for a declared object at the same time), or it's known.
            if hasObjectEntry {
                // Either state for hasFileEntry is fine.
            }
            else {
                // Must *not* have a file entry.
                guard !hasFileEntry else {
                    throw SyncServerError.internalError("No object entry but have a file entry!")
                }
            }
        }
    }
}

extension Array where Element == FileInfo {
    enum FileInfoError: Error {
        case noCreationDate
        case badUUID
        case badVersion
        case badLabel
        case noObjectType
    }
    
    // Reformat an array of [FileInfo] objects to [IndexObject] so that client's don't need to aggregate files into objects.
    func toIndexObjects() throws -> [IndexObject] {
        guard count > 0 else {
            return []
        }
        
        let fileGroups = Partition.array(self, using: \.fileGroupUUID)
        
        var indexObjects = [IndexObject]()
        
        for fileGroup in fileGroups {
            var downloadFiles = [DownloadFile]()

            var creationDate: Date!
            
            for file in fileGroup {
                guard let fileCreationDate = file.creationDate else {
                    throw FileInfoError.noCreationDate
                }
                
                if creationDate == nil {
                    creationDate = fileCreationDate
                }
                else {
                    creationDate = Swift.min(creationDate, fileCreationDate)
                }
                
                guard let fileUUID = try UUID.from(file.fileUUID) else {
                    throw FileInfoError.badUUID
                }
                
                guard let fileVersion = file.fileVersion else {
                    throw FileInfoError.badVersion
                }
                
                guard let fileLabel = file.fileLabel else {
                    throw FileInfoError.badLabel
                }
                
                downloadFiles += [DownloadFile(uuid: fileUUID, fileVersion: fileVersion, fileLabel: fileLabel)]
            }
            
            let firstFile = fileGroup[0]
            
            guard let objectCreationDate = creationDate else {
                throw FileInfoError.noCreationDate
            }
            
            guard let sharingGroupUUID = try UUID.from(firstFile.sharingGroupUUID),
                let fileGroupUUID = try UUID.from(firstFile.fileGroupUUID) else {
                throw FileInfoError.badUUID
            }
            
            guard let objectType = firstFile.objectType else {
                throw FileInfoError.noObjectType
            }
            
            // If any of the files in the file group is deleted, going to consider the whole object deleted.
            let anyDeleted = fileGroup.filter {$0.deleted == true}
            let objectDeleted = anyDeleted.count > 0
            
            indexObjects += [IndexObject(sharingGroupUUID: sharingGroupUUID, fileGroupUUID: fileGroupUUID, objectType: objectType, creationDate: objectCreationDate, deleted: objectDeleted, downloads: downloadFiles)]
        }

        return indexObjects
    }
}
