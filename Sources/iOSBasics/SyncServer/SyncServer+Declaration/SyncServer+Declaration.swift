
import Foundation
import SQLite

extension SyncServer {
    // This method is synchronous.
    func declarationHelper(object: DeclarableObject & ObjectDownloadHandler) throws {
        let fileLabels = object.declaredFiles.map {$0.fileLabel}
        guard Set<String>(fileLabels).count == fileLabels.count else {
            throw SyncServerError.duplicateFileLabel
        }
        
        // Make sure all files have at least one mime type
        for fileDeclaration in object.declaredFiles {
            guard fileDeclaration.mimeTypes.count > 0 else {
                throw SyncServerError.noMimeTypes
            }
        }
        
        let result = try DeclaredObjectModel.lookupMatches(object: object, db: db)
        
        switch result {
        case .noMatch:
            let newObject = try DeclaredObjectModel(db: db, object: object)
            try newObject.insert()
            objectDeclarations[object.objectType] = object
            
        case .matchesWithSameFiles:
            break
            
        case .matchesWithAdditional(object: let existingObject, files: let newFiles):
            try existingObject.update(setters:
                DeclaredObjectModel.filesDataField.description <-
                    try DeclaredObjectModel.encode(files: newFiles))
            objectDeclarations[object.objectType] = object
        }
    }
}
