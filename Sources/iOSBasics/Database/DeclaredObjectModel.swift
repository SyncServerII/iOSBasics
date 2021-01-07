
import Foundation
import SQLite
import ServerShared
import iOSShared

class DeclaredObjectModel: DatabaseModel, DeclarableObjectBasics, Equatable {
    let db: Connection
    var id: Int64!
    
    static let objectTypeField = Field("objectType", \M.objectType)
    var objectType: String
    
    static let filesDataField = Field("filesData", \M._filesData)
    private(set) var _filesData: Data
    
    func set(files: [FileDeclaration]) throws {
        _filesData = try Self.encode(files: files)
    }
    
    func getFiles() throws -> [FileDeclaration] {
        return try Self.decode(from: _filesData)
    }
    
    func getFile(with fileLabel: String) throws -> FileDeclaration {
        let file = try getFiles().filter {$0.fileLabel == fileLabel}
        guard file.count == 1 else {
            throw DatabaseError.notExactlyOneWithFileLabel
        }
        
        return file[0]
    }
    
    static func encode(files: [FileDeclaration]) throws -> Data {
        return try JSONEncoder().encode(files)
    }
    
    static func decode(from data: Data) throws -> [FileDeclaration] {
        return try JSONDecoder().decode([FileDeclaration].self, from: data)
    }
    
    init(db: Connection,
        id: Int64! = nil,
        objectType: String,
        files: [FileDeclaration]) throws {
        self.db = db
        self.id = id
        self.objectType = objectType
        
        guard files.count > 0 else {
            throw DatabaseError.noFileDeclarations
        }
        
        _filesData = try Self.encode(files: files)
    }
    
    init(db: Connection,
        id: Int64! = nil,
        object: DeclarableObject) throws {
        self.db = db
        self.id = id
        
        guard object.declaredFiles.count > 0 else {
            throw DatabaseError.noFileDeclarations
        }
        
        let files = object.declaredFiles.map {
            FileDeclaration(fileLabel: $0.fileLabel, mimeTypes: $0.mimeTypes, changeResolverName: $0.changeResolverName)
        }
        
        self.objectType = object.objectType
        _filesData = try Self.encode(files: files)
    }
    
    static func ==(lhs: DeclaredObjectModel, rhs: DeclaredObjectModel) -> Bool {
        guard let lhsFiles = try? lhs.getFiles(),
            let rhsFiles = try? rhs.getFiles() else {
            logger.error("Could not get files!")
            return false
        }
        
        return lhs.id == rhs.id
            && lhs.objectType == rhs.objectType
            && equal(lhsFiles, rhsFiles)
    }
    
    static func createTable(db: Connection) throws {
        try startCreateTable(db: db) { t in
            t.column(idField.description, primaryKey: true)
            t.column(objectTypeField.description, unique: true)
            t.column(filesDataField.description)
        }
    }
    
    static func rowToModel(db: Connection, row: Row) throws -> DeclaredObjectModel {
        let data = row[Self.filesDataField.description]
        let files = try decode(from: data)
        return try DeclaredObjectModel(db: db,
            id: row[Self.idField.description],
            objectType: row[Self.objectTypeField.description],
            files: files
        )
    }

    func insert() throws {
        try doInsertRow(db: db, values:
            Self.objectTypeField.description <- objectType,
            Self.filesDataField.description <- _filesData
        )
    }
}

extension DeclaredObjectModel {
    // Get a DeclarableObject to represent the DeclaredObjectModel and its component declared files. throws DatabaseModelError.noObject if no object found.
    static func lookup(objectType: String, db: Connection) throws -> ObjectDeclaration {
        guard let model = try DeclaredObjectModel.fetchSingleRow(db: db, where: objectType == DeclaredObjectModel.objectTypeField.description) else {
            throw DatabaseError.noObject
        }
        
        return ObjectDeclaration(objectType: objectType, declaredFiles: try model.getFiles())
    }
    
    enum MatchResult {
        case noMatch
        case matchesWithSameFiles
        case matchesWithAdditional(object: DeclaredObjectModel, files: [FileDeclaration])
    }
    
    // Lookup matches for the object. It must either be new, or all files must be in existing object.
    static func lookupMatches(object: DeclarableObject, db: Connection) throws -> MatchResult {
        let declaredObject = try DeclaredObjectModel.fetchSingleRow(db: db,
            where: object.objectType == DeclaredObjectModel.objectTypeField.description)

        guard let existingObject = declaredObject else {
            // New declaration
            return .noMatch
        }
        
        let existingObjectFiles = try existingObject.getFiles()
                
        let newObjectFiles = object.declaredFiles.map {
            FileDeclaration(fileLabel: $0.fileLabel, mimeTypes: $0.mimeTypes, changeResolverName: $0.changeResolverName)
        }
        
        var newObjectFilesSet = Set<FileDeclaration>(newObjectFiles)
                
        // Make sure all of the file declarations in the existing object are in the new object.

        for existingObjectFile in existingObjectFiles {
            // Check if the fileLabel for the `existingObjectFile` is in one of the `newObjectFilesSet`
            
            var contained = false
            for newFile in newObjectFilesSet {
                if existingObjectFile.fileLabel == newFile.fileLabel {
                    guard existingObjectFile == newFile else {
                        throw SyncServerError.matchingFileLabelButOtherDifferences
                    }
                    contained = true
                    break
                }
            }
            
            if contained {
                newObjectFilesSet.remove(existingObjectFile)
            }
            else {
                throw SyncServerError.objectDoesNotHaveAllExistingFiles
            }
        }
        
        if newObjectFiles.count > 0 {
            return .matchesWithAdditional(object: existingObject, files: newObjectFiles)
        }
        else {
            return .matchesWithSameFiles
        }
    }
    
    // The upload object must exist. Matches `UploadableObject` `fileLabel`'s against the `DeclaredObjectModel` `fileLabel`'s.
    static func lookup(upload: UploadableObject, db: Connection) throws -> DeclaredObjectModel {
        guard let declaredObject = try DeclaredObjectModel.fetchSingleRow(db: db,
            where: upload.objectType == DeclaredObjectModel.objectTypeField.description) else {
            throw SyncServerError.noObject
        }
            
        let uploadFileLabels = upload.uploads.map {$0.fileLabel}
        let uploadFileLabelsSet = Set<String>(uploadFileLabels)
        
        guard uploadFileLabelsSet.count == uploadFileLabels.count else {
            throw SyncServerError.duplicateFileLabel
        }
        
        let declaredLabelsSet = Set<String>(try declaredObject.getFiles().map {$0.fileLabel})
        
        // Make sure all of the fileLabels are in the declared object.
        let diff = declaredLabelsSet.subtracting(uploadFileLabelsSet)
        guard declaredLabelsSet.count == uploadFileLabelsSet.count + diff.count else {
            throw SyncServerError.someFileLabelsNotInDeclaredObject
        }
        
        return declaredObject
    }
}


