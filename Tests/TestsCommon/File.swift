//
//  MigrationRunnerFake.swift
//  
//
//  Created by Christopher G Prince on 5/15/21.
//

import Foundation
import iOSShared

class MigrationRunnerFake: MigrationRunner {    
    func run(migrations: [Migration], contentChanges: [Migration]) throws {
        for migration in migrations {
            try migration.apply()
        }
    }
}
