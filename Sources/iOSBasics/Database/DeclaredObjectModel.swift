//
//  SyncedObjectModel.swift
//  
//
//  Created by Christopher G Prince on 9/1/20.
//

import Foundation
import SQLite

// DeclaredObject's (see DeclaredObjectModel for the declared files).

class DeclaredObjectModel: DatabaseModel, DeclarableObjectBasics, Equatable {
    let db: Connection
    var id: Int64!
    
    static let fileGroupUUIDField = Field("fileGroupUUID", \M.fileGroupUUID)
    var fileGroupUUID: UUID
    
    static let objectTypeField = Field("objectType", \M.objectType)
    var objectType: String
    
    static let sharingGroupUUIDField = Field("sharingGroupUUID", \M.sharingGroupUUID)
    var sharingGroupUUID: UUID
        
    init(db: Connection,
        id: Int64! = nil,
        fileGroupUUID: UUID,
        objectType: String,
        sharingGroupUUID: UUID) throws {
        self.db = db
        self.id = id
        self.fileGroupUUID = fileGroupUUID
        self.objectType = objectType
        self.sharingGroupUUID = sharingGroupUUID
    }
    
    static func == (lhs: DeclaredObjectModel, rhs: DeclaredObjectModel) -> Bool {
        return lhs.id == rhs.id && lhs.compare(to: rhs)
    }
    
    static func createTable(db: Connection) throws {
        try startCreateTable(db: db) { t in
            t.column(idField.description, primaryKey: true)
            t.column(fileGroupUUIDField.description)
            t.column(objectTypeField.description)
            t.column(sharingGroupUUIDField.description)
        }
    }
    
    static func rowToModel(db: Connection, row: Row) throws -> DeclaredObjectModel {
        return try DeclaredObjectModel(db: db,
            id: row[Self.idField.description],
            fileGroupUUID: row[Self.fileGroupUUIDField.description],
            objectType: row[Self.objectTypeField.description],
            sharingGroupUUID: row[Self.sharingGroupUUIDField.description]
        )
    }

    func insert() throws {
        try doInsertRow(db: db, values:
            Self.fileGroupUUIDField.description <- fileGroupUUID,
            Self.objectTypeField.description <- objectType,
            Self.sharingGroupUUIDField.description <- sharingGroupUUID
        )
    }
}

extension DeclaredObjectModel {
    // Get a DeclarableObject to represent the DeclaredObjectModel and its component declared files. throws DatabaseModelError.noObject if no object found for declObjectId.
    static func lookupDeclarableObject(declObjectId: UUID, db: Connection) throws -> some DeclarableObject {
        let models:[DeclaredObjectModel] = try DeclaredObjectModel.fetch(db: db, where: declObjectId == DeclaredObjectModel.fileGroupUUIDField.description)
        
        switch models.count {
        case 0:
            throw DatabaseModelError.noObject
            
        case 1:
            break
            
        default:
            throw DatabaseModelError.tooManyObjects
        }
        
        let model = models[0]
                    
        let declaredFilesInDatabase = try DeclaredFileModel.fetch(db: db, where: declObjectId == DeclaredFileModel.fileGroupUUIDField.description).map { FileDeclaration(uuid: $0.uuid, mimeType: $0.mimeType, cloudStorageType: $0.cloudStorageType, appMetaData: $0.appMetaData, changeResolverName: $0.changeResolverName) }
        
        let files = Set<FileDeclaration>(declaredFilesInDatabase)
        
        let declObject = ObjectDeclaration(fileGroupUUID: model.fileGroupUUID, objectType: model.objectType, sharingGroupUUID: model.sharingGroupUUID, declaredFiles: files)
        
        return declObject
    }
}

