
import Foundation
import SQLite
import ServerShared

/*
extension SyncServer {
    func objectsNeedingDeletionHelper() throws -> [ObjectDeclaration] {
        let entries = try DirectoryEntry.fetch(db: db, where: DirectoryEntry.deletedOnServerField.description == true &&
            DirectoryEntry.deletedLocallyField.description == false)

        // Objects are organized by file groups. So, partition these by file group.
        let fileGroups = Partition.array(entries, using: \.fileGroupUUID)
        
        var objects = [ObjectDeclaration]()

        for fileGroup in fileGroups {
            guard fileGroup.count > 0 else {
                throw SyncServerError.internalError("No files in file group: Should not get here.")
            }
            
            let entry = fileGroup[0]
            
            let object = try DeclaredObjectModel.lookupDeclarableObject(fileGroupUUID: entry.fileGroupUUID, db: db)
            
            objects += [object]
        }
        
        return objects
    }
    
    public func objectDeletedHelper<DECL: DeclarableObject>(object: DECL) throws {
        let lookupObject = try DeclaredObjectModel.lookupDeclarableObject(fileGroupUUID: object.fileGroupUUID, db: db)
        guard lookupObject.declCompare(to: object) else {
            throw SyncServerError.objectNotDeclared
        }
                
        let entries = try object.declaredFiles.map { file throws -> DirectoryEntry in
            guard let entry = try DirectoryEntry.fetchSingleRow(db: db, where: DirectoryEntry.fileUUIDField.description == file.uuid) else {
                throw SyncServerError.internalError("Could not get DirectoryEntry")
            }
            return entry
        }
        
        guard (entries.filter { $0.deletedOnServer }).count == entries.count else {
            throw SyncServerError.fileNotDeletedOnServer
        }
        
        for entry in entries {
            try entry.update(setters:
                DirectoryEntry.deletedLocallyField.description <- true)
        }
    }
}
*/
