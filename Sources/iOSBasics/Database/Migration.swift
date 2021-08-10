//
//  Migration.swift
//  
//
//  Created by Christopher G Prince on 5/8/21.
//

import Foundation
import iOSShared
import SQLite
import PersistentValue

enum SpecificMigration {
    public static let m2021_5_8: Int32 = 2021_5_8
    public static let m2021_05_30: Int32 = 2021_05_30
    public static let m2021_06_03: Int32 = 2021_06_03
    public static let m2021_08_02: Int32 = 2021_08_02
    public static let m2021_08_07: Int32 = 2021_08_07
}

class Migration: VersionedMigrationRunner {
    // From my evaluation so far, using PersistentValue with user defaults doesn't work. See also https://github.com/sunshinejr/SwiftyUserDefaults/issues/282
    private static let _schemaVersionDeprecated = try! PersistentValue<Int>(name: "iOSBasics.MigrationController.schemaVersion", storage: .userDefaults)
    private static let _schemaVersion = try! PersistentValue<Int>(name: "iOSBasics.MigrationController.schemaVersion", storage: .file)

    // Migrate from using user defaults to using file-based storage with `PersistentValue`. Only does the migration if needed. Should be able remove this after getting a TestFlight build or two to Rod and Dany. Don't need to include this in final 2.0.0 release. Can remove `_schemaVersionDeprecated` then too.
    private func migrate() {
        if let value = Self._schemaVersionDeprecated.value,
            Self._schemaVersion.value == nil {
            Self._schemaVersion.value = value
        }
    }
    
    static var schemaVersion: Int32? {
        get {
            if let value = _schemaVersion.value {
                return Int32(value)
            }
            return 0
        }
        
        set {
            if let value = newValue {
                _schemaVersion.value = Int(value)
            }
            else {
                _schemaVersion.value = nil
            }
        }
    }
    
    let db: Connection
    
    init(db:Connection) throws {
        self.db = db
        migrate()
    }
    
    // These migrations can only do column additions (and possibly deletions). See https://github.com/SyncServerII/Neebla/issues/26
    static func metadata(db: Connection) -> [iOSShared.Migration] {
        return [
            MigrationObject(version: SpecificMigration.m2021_5_8, apply: {
                try DownloadFileTracker.migration_2021_5_8(db: db)
            }),
            MigrationObject(version: SpecificMigration.m2021_05_30, apply: {
                try UploadFileTracker.migration_2021_5_30(db: db)
            }),
            MigrationObject(version: SpecificMigration.m2021_06_03, apply: {
                try SharingEntry.migration_2021_6_3(db: db)
            }),
            MigrationObject(version: SpecificMigration.m2021_08_02, apply: {
                try UploadFileTracker.migration_2021_8_2(db: db)
            }),
            MigrationObject(version: SpecificMigration.m2021_08_07, apply: {
                try UploadFileTracker.migration_2021_8_7(db: db)
            }),
        ]
    }
    
    // These migrations can only do content changes to rows. See https://github.com/SyncServerII/Neebla/issues/26
    static func content(configuration: Configuration, db: Connection) -> [iOSShared.Migration] {
        return [
            MigrationObject(version: SpecificMigration.m2021_08_02, apply: {
                try UploadFileTracker.migration_2021_8_2_updateUploads(
                    configuration: configuration, db: db)
            }),
        ]
    }
}
