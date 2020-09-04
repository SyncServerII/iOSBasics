//
//  File.swift
//  
//
//  Created by Christopher G Prince on 9/3/20.
//

import Foundation
import SQLite

extension SyncServer {
    // throws SyncServerError.noObject if no object found for declObjectId
    func lookupDeclObject(declObjectId: UUID) throws -> some DeclaredObject {
        let models:[DeclaredObjectModel] = try DeclaredObjectModel.fetch(db: db, where: declObjectId == DeclaredObjectModel.fileGroupUUIDField.description)
        switch models.count {
        case 0:
            throw SyncServerError.tooManyObjects
        case 1:
            break
        default:
            throw SyncServerError.tooManyObjects
        }
        
        let model = models[0]
                    
        let declaredFilesInDatabase = try DeclaredFileModel.fetch(db: db, where: declObjectId == DeclaredFileModel.fileGroupUUIDField.description).map { FileDecl(uuid: $0.uuid, mimeType: $0.mimeType, appMetaData: $0.appMetaData, changeResolverName: $0.changeResolverName) }
        
        let files = Set<FileDecl>(declaredFilesInDatabase)
        
        let declObject = DeclObject(fileGroupUUID: model.fileGroupUUID, objectType: model.objectType, sharingGroupUUID: model.sharingGroupUUID, declaredFiles: files)
        
        return declObject
    }
}
