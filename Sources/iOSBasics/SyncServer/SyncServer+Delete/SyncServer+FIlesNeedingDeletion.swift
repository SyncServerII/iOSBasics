
import Foundation
import SQLite
import ServerShared

extension SyncServer {
    func objectsNeedingLocalDeletionHelper() throws -> [UUID] {
        let objectEntries = try DirectoryObjectEntry.fetch(db: db, where: DirectoryObjectEntry.deletedOnServerField.description == true &&
            DirectoryObjectEntry.deletedLocallyField.description == false)

        // Objects are organized by file groups. So, partition these by file group.
        let fileGroups = Partition.array(objectEntries, using: \.fileGroupUUID)
        
        var fileGroupUUIDs = [UUID]()

        for fileGroup in fileGroups {
            guard fileGroup.count > 0 else {
                throw SyncServerError.internalError("No files in file group: Should not get here.")
            }
                        
            fileGroupUUIDs += [fileGroup[0].fileGroupUUID]
        }
        
        return fileGroupUUIDs
    }
    
    public func objectDeletedLocallyHelper(object fileGroupUUID: UUID) throws {
        guard let objectInfo = try DirectoryObjectEntry.lookup(fileGroupUUID: fileGroupUUID, db: db) else {
            throw SyncServerError.noObject
        }
        
        guard !objectInfo.objectEntry.deletedLocally else {
            throw SyncServerError.attemptToDeleteAnAlreadyDeletedFile
        }
        
        guard objectInfo.objectEntry.deletedOnServer else {
            throw SyncServerError.attemptToDeleteAnAlreadyDeletedFile
        }
        
        for fileEntry in objectInfo.allFileEntries {
            guard !fileEntry.deletedLocally else {
                throw SyncServerError.attemptToDeleteAnAlreadyDeletedFile
            }
            
            guard fileEntry.deletedOnServer else {
                throw SyncServerError.attemptToDeleteAnAlreadyDeletedFile
            }
        }
        
        try objectInfo.objectEntry.update(setters: DirectoryObjectEntry.deletedLocallyField.description <- true)
        
        for fileEntry in objectInfo.allFileEntries {
            try fileEntry.update(setters:
                DirectoryFileEntry.deletedLocallyField.description <- true)
        }
    }
}
