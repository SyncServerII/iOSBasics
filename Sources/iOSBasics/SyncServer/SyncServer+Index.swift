
import Foundation
import SQLite
import ServerShared

extension SyncServer {
    // Operates asynchronously.
    func getIndex(sharingGroupUUID: UUID) {
        api.index(sharingGroupUUID: sharingGroupUUID) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let indexResult):
                self._sharingGroups = indexResult.sharingGroups

                guard let fileIndex = indexResult.fileIndex else {
                    self.delegator { [weak self] delegate in
                        guard let self = self else { return }
                        delegate.error(self, error: SyncServerError.internalError("Nil fileIndex"))
                    }
                    return
                }
                
                do {
                    try self.upsert(sharingGroups: indexResult.sharingGroups)
                    try self.upsert(fileIndex: fileIndex, sharingGroupUUID: sharingGroupUUID)
                } catch {
                    self.delegator { [weak self] delegate in
                        guard let self = self else { return }
                        delegate.error(self, error: error)
                    }
                    return
                }

                self.delegator { [weak self] delegate in
                    guard let self = self else { return }
                    delegate.syncCompleted(self)
                }
                
            case .failure(let error):
                self.delegator { [weak self] delegate in
                    guard let self = self else { return }
                    delegate.error(self, error: error)
                }
            }
        }
    }
    
    private func upsert(sharingGroups: [ServerShared.SharingGroup]) throws {
        for sharingGroup in sharingGroups {
            try SharingEntry.upsert(sharingGroup: sharingGroup, db: db)
        }
    }
    
    func upsert(fileIndex: [FileInfo], sharingGroupUUID: UUID) throws {
        let fileGroups = Partition.array(fileIndex, using: \.fileGroupUUID)
        
        for fileGroup in fileGroups {
            guard fileGroup.count > 0 else {
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
            
            // Where do I get object types from?
            
            let objectBasics = ObjectBasics(fileGroupUUID: fileGroupUUID, objectType: "TBD", sharingGroupUUID: sharingGroupUUID)
            let object = try DeclaredObjectModel.upsert(object: objectBasics, db: db)
            
            for file in fileGroup {
                try DeclaredFileModel.upsert(fileInfo: file, object: object, db: db)
                try DirectoryEntry.upsert(fileInfo: file, db: db)
            }
        }
    }
}
