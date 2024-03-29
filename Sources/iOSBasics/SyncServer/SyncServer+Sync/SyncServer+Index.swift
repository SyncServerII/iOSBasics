
import Foundation
import SQLite
import ServerShared
import iOSShared

extension SyncServer {
    // Operates asynchronously.
    func getIndex(sharingGroupUUID: UUID?, completion: (()->())? = nil) {
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
                    
                    completion?()
                    return
                }
                
                guard let sharingGroupUUID = sharingGroupUUID else {
                    do {
                        let noIndexResult = try self.getNoIndexResult(indexResult: indexResult)
                        self.delegator { [weak self] delegate in
                            guard let self = self else { return }
                            delegate.syncCompleted(self, result: .noIndex(noIndexResult))
                        }
                    } catch let error {
                        self.delegator { [weak self] delegate in
                            guard let self = self else { return }
                            delegate.userEvent(self, event: .error(error))
                        }
                    }
                    
                    completion?()
                    return
                }

                guard let fileIndex = indexResult.fileIndex else {
                    self.delegator { [weak self] delegate in
                        guard let self = self else { return }
                        delegate.userEvent(self, event: .error(SyncServerError.internalError("Nil fileIndex but a sharing group was given.")))                        
                    }
                    
                    completion?()
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
                    
                    completion?()
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
            
            completion?()
        }
    }
    
    // `sharingGroups` is the full set of sharing groups returned from the server.
    private func upsert(sharingGroups: [ServerShared.SharingGroup]) throws {
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
        
        let fileIndex = try checkInvariants(fileIndex: fileIndex, sharingGroupUUID: sharingGroupUUID)
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

            let _ = try DirectoryObjectEntry.matchUpsert(fileInfo: firstFile, objectType: objectType, db: db)
            
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
                // Not going to throw an error here as this will stop processing of the remaining file groups. Just log an error and continue.
                logger.error("Some but not all of a file group deleted: fileGroup: \(fileGroupUUID); deletedCount = \(deletedCount); fileGroup.count= \(fileGroup.count)")
                continue
            }
            
            if deletedCount > 0 {
                delegator { [weak self] delegate in
                    guard let self = self else { return }
                    delegate.downloadDeletion(self, details: .fileGroup(fileGroupUUID))
                }
            }
        }
    }
    
    // Returns possibly filtered [FileInfo] -- elements removed if the file label isn't known.
    private func checkInvariants(fileIndex: [FileInfo], sharingGroupUUID: UUID) throws -> [FileInfo] {
        // All files must have the sharingGroupUUID
        let sharingGroups = Set<String>(fileIndex.compactMap {$0.sharingGroupUUID})
        guard sharingGroups.count == 1 else {
            throw SyncServerError.internalError("Not just one sharing group")
        }
        
        guard sharingGroupUUID.uuidString == fileIndex[0].sharingGroupUUID else {
            throw SyncServerError.internalError("sharingGroupUUID didn't match")
        }
        
        var result = [FileInfo]()
        
        for file in fileIndex {
            guard let fileUUID = try UUID.from(file.fileUUID) else {
                throw SyncServerError.internalError("A file UUID string couldn't be converted to a UUID: \(String(describing: file.fileUUID))")
            }
            
            guard let fileGroupUUID = try UUID.from(file.fileGroupUUID) else {
                throw SyncServerError.internalError("A file group UUID string couldn't be converted to a UUID: \(String(describing: file.fileGroupUUID))")
            }

            var hasFileEntry = false
            var hasObjectEntry = false

            let objectType = try helperDelegate.getObjectType(file: file)
            
            // We might want to weaken this later, but for initial testing, fail if we don't know about the declared object. One reason to weaken this later is for migration purposes. Some app instance could have been upgraded, but a current one doesn't yet know about a new object type.
            guard let declaredObject = try DeclaredObjectModel.fetchSingleRow(db: db, where: DeclaredObjectModel.objectTypeField.description == objectType) else {
                throw SyncServerError.internalError("No declared object!")
            }
            
            // This doesn't do specific validity checking on the file label.
            let fileLabel = try file.getFileLabel(objectType: objectType, objectDeclarations: objectDeclarations)

            let fileDeclaration:FileDeclaration
            
            do {
                // This *does* check for a specifically declared file label-- and throws an error if it's not declared.
                fileDeclaration = try declaredObject.getFile(with: fileLabel)
            } catch let error {
                logger.warning("No locally declared label for object: \(error): \(fileLabel)")
                // Skip adding this `FileInfo`.
                continue
            }
            
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
            
            result += [file]
        }
        
        return result
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
            var mostRecentUpdateDate: Date?
            
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
                
                if let updateDate = file.updateDate {
                    if let mrud = mostRecentUpdateDate {
                        mostRecentUpdateDate = Swift.max(mrud, updateDate)
                    }
                    else {
                        mostRecentUpdateDate = updateDate
                    }
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
                
                // Not overtly indicating in `DownloadFile` that the file is deleted or not deleted. That comes at the object level in the `IndexObject`-- see below.
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
            
            indexObjects += [IndexObject(sharingGroupUUID: sharingGroupUUID, fileGroupUUID: fileGroupUUID, objectType: objectType, creationDate: objectCreationDate, updateDate: mostRecentUpdateDate, deleted: objectDeleted, downloads: downloadFiles)]
        }

        return indexObjects
    }
}
