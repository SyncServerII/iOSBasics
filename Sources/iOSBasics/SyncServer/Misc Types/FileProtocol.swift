//
//  File.swift
//  
//
//  Created by Christopher G Prince on 10/7/20.
//

import Foundation
import ServerShared

public protocol File {
    var uuid: UUID {get}
}

/*
public extension File {
    static func hasDistinctUUIDs(in set: Set<Self>) -> Bool {
        let uuids = Set<UUID>(set.map {$0.uuid})
        return uuids.count == set.count
    }
}
*/

/*
public extension DeclarableFile {
    // Returns true iff objects are the same.
    static func compare<FILE1: DeclarableFile, FILE2: DeclarableFile>(
        first: Set<FILE1>, second: Set<FILE2>) -> Bool {
        let firstUUIDs = Set<UUID>(first.map { $0.uuid })
        let secondUUIDs = Set<UUID>(second.map { $0.uuid })
        
        guard firstUUIDs == secondUUIDs else {
            return false
        }
        
        for uuid in firstUUIDs {
            guard let a = first.first(where: {$0.uuid == uuid}),
                let b = second.first(where: {$0.uuid == uuid}) else {
                return false
            }
            
            return a.compare(to: b)
        }
        
        return true
    }
}
*/


/*
public protocol DeclarableObjectBasics {
    // An id for this Object. This is required because we're organizing DeclarableObject's around these UUID's. AKA, declObjectId
    var fileGroupUUID: UUID { get }

    // An id for the group of users that have access to this Object
    var sharingGroupUUID: UUID { get }
}
*/

/*
    // Get a specific `DeclarableFile` from a declaration.
    static func fileDeclaration<OBJ: DeclarableObject>(forFileUUID uuid: UUID, from declaration: OBJ) throws -> some DeclarableFile {
        let declaredFiles = declaration.declaredFiles.filter {$0.uuid == uuid}
        guard declaredFiles.count == 1,
            let declaredFile = declaredFiles.first else {
            throw SyncServerError.internalError("Not just one declared file: \(declaredFiles.count)")
        }
        
        return declaredFile
    }
 */

