import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
@testable import TestsCommon

class UploadQueueTests: APITestCase {
    var db: Connection!
    
    override func setUpWithError() throws {
        db = try Connection(.inMemory)
        let hashingManager = HashingManager()
//let config = Configuration(appGroupIdentifier: nil, sqliteDatabasePath: "", serverURL: <#T##URL#>, minimumServerVersion: <#T##Version?#>, failoverMessageURL: <#T##URL?#>, cloudFolderName: <#T##String?#>)
//        SyncServer(hashingManager: hashingManager, db: db, configuration: <#T##Configuration#>, delegate: <#T##SyncServerDelegate#>)
    }

    override func tearDownWithError() throws {
    }
}
