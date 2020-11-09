
import Foundation
import SQLite

extension SyncServer {
    func declarationHelper(object: DeclarableObject & ObjectDownloadHandler) throws {
        let fileLabels = object.declaredFiles.map {$0.fileLabel}
        guard Set<String>(fileLabels).count == fileLabels.count else {
            throw SyncServerError.duplicateFileLabel
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
