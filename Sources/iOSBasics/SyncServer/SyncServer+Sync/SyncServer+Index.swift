
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
                        delegate.error(self, error: .error(error))
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
                        delegate.error(self, error: .error(SyncServerError.internalError("Nil fileIndex but a sharing group was given.")))
                    }
                    return
                }
                
                do {
                    try self.upsert(fileIndex: fileIndex, sharingGroupUUID: sharingGroupUUID)
                } catch {
                    self.delegator { [weak self] delegate in
                        guard let self = self else { return }
                        delegate.error(self, error: .error(error))
                    }
                    return
                }

                self.delegator { [weak self] delegate in
                    guard let self = self else { return }
                    delegate.syncCompleted(self, result: .index(sharingGroupUUID: sharingGroupUUID, index: fileIndex))
                }
                
            case .failure(let error):
                self.delegator { [weak self] delegate in
                    guard let self = self else { return }
                    delegate.error(self, error: .error(error))
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
            throw SyncServerError.internalError("Not at least one element")
        }
        
        //try checkInvariants(fileIndex: fileIndex, sharingGroupUUID: sharingGroupUUID)
        let fileGroups = Partition.array(fileIndex, using: \.fileGroupUUID)
        
        for fileGroup in fileGroups {
            guard fileGroup.count > 0 else {
                throw SyncServerError.internalError("Not at least one element")
            }
            
            var objectType: String?
            
            // All objectTypes across the fileGroup must be either nil, or the same string value
            let objectTypes = Set<String>(fileGroup.compactMap { $0.objectType })
            var objectModel:DeclaredObjectModel?
            switch objectTypes.count {
            case 0:
                logger.warning("No object type for fileGroup: \(String(describing: fileGroup[0].fileGroupUUID))")
            case 1:
                objectType = objectTypes.first
                objectModel = try DeclaredObjectModel.fetchSingleRow(db: db, where: DeclaredObjectModel.objectTypeField.description == objectType!)
            default:
                throw SyncServerError.internalError("Not at least one element")
            }
            
            let firstFile = fileGroup[0]
            
            guard let fileGroupUUIDString = firstFile.fileGroupUUID,
                let fileGroupUUID = UUID(uuidString: fileGroupUUIDString) else {
                throw SyncServerError.internalError("Could not get fileGroupUUID field")
            }
            
            guard sharingGroupUUID.uuidString == firstFile.sharingGroupUUID else {
                throw SyncServerError.internalError("sharingGroupUUID didn't match")
            }
            
            let _ = try DirectoryObjectEntry.matchSert(fileInfo: firstFile, db: db)
            
            var deletedCount = 0
            
            for file in fileGroup {
                let (fileEntry, deleted) = try DirectoryFileEntry.upsert(fileInfo: file, db: db)
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
    
    /*
    private func checkInvariants(fileIndex: [FileInfo], sharingGroupUUID: UUID) throws {
        // Make sure all fileIndex's have the given sharing group.
        guard (fileIndex.filter {$0.sharingGroupUUID == sharingGroupUUID.uuidString}).count == fileIndex.count else {
            throw SyncServerError.internalError("Some of the files in the file index didn't have the downloaded sharing group.")
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

            var hasDirectoryEntry = false
            var hasDeclaredFile = false
            var hasDeclaredObject = false

            // If a fileIndex fileUUID has a DirectoryFileEntry or a DirectoryObjectEntry then their main (static) components must not have changed.
            
            if let declaredObject = try DeclaredObjectModel.fetchSingleRow(db: db, where: DeclaredObjectModel.fileGroupUUIDField.description == fileGroupUUID) {
                
                hasDeclaredObject = true
                
                guard declaredObject.sameInvariants(fileInfo: file) else {
                    throw SyncServerError.internalError("Invariants of a FileInfo changed.")
                }
            }
            
            if let entry = try DirectoryEntry.fetchSingleRow(db: db, where: DirectoryEntry.fileUUIDField.description == fileUUID) {
                
                hasDirectoryEntry = true
                
                guard entry.sameInvariants(fileInfo: file) else {
                    throw SyncServerError.internalError("Invariants of a FileInfo changed.")
                }
            }
            
            if let declaredFile = try DeclaredFileModel.fetchSingleRow(db: db, where: DeclaredFileModel.uuidField.description == fileUUID) {
                
                hasDeclaredFile = true
                
                guard declaredFile.sameInvariants(fileInfo: file) else {
                    throw SyncServerError.internalError("Invariants of a FileInfo changed.")
                }
            }
            
            if hasDeclaredObject {
                // Two possible cases with an existing declared object: Either this is a new file for the declared object (i.e., clients don't have to upload all files for a declared object at the same time), or it's known.

                // Either we have both the directory entry and declared file or we have neither.
                guard hasDirectoryEntry == hasDeclaredFile else {
                    throw SyncServerError.internalError("Had declared object, but inconsistent state for declared file and directory entry.")
                }
            }
            else {
                guard hasDirectoryEntry == hasDeclaredFile && hasDeclaredFile == hasDeclaredObject else {
                    throw SyncServerError.internalError("A FileInfo in the fileIndex had corrupted database objects.")
                }
            }
        }
    }
    */
}
