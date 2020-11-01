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
        try DirectoryObjectEntry.createTable(db: db)
        try DirectoryFileEntry.createTable(db: db)
        try NetworkCache.createTable(db: db)
        try SharingEntry.createTable(db: db)
        try UploadFileTracker.createTable(db: db)
        try DeclaredObjectModel.createTable(db: db)
        try UploadObjectTracker.createTable(db: db)
        try WorkingParameters.createTable(db: db)
        try WorkingParameters.setup(db: db)
        try UploadDeletionTracker.createTable(db: db)
        try DownloadObjectTracker.createTable(db: db)
        try DownloadFileTracker.createTable(db: db)
    }
}
