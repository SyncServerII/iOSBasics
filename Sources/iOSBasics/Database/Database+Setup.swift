//
//  Database+Setup.swift
//  
//
//  Created by Christopher G Prince on 9/2/20.
//

import Foundation
import SQLite

extension Database {
    static func setup(db: Connection) throws {
        try DirectoryEntry.createTable(db: db)
        try NetworkCache.createTable(db: db)
        try SharingEntry.createTable(db: db)
        try SyncedObjectModel.createTable(db: db)
        try UploadFileTracker.createTable(db: db)
    }
}
