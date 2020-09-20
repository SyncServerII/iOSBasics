
import XCTest
@testable import iOSBasics
import iOSSignIn
@testable import iOSDropbox
import ServerShared
import iOSShared
import SQLite

class ServerAPI_SharingGroups: XCTestCase, UserSetup, APITests, ServerAPIDelegator, ServerBasics, TestFiles {
    var hashingManager: HashingManager!
    var api: ServerAPI!
    var deviceUUID: UUID!
    var database: Connection!
    let config = Configuration.defaultTemporaryFiles
    var handlers = DelegateHandlers()
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        handlers = DelegateHandlers()
        handlers.user = try dropboxUser()
        deviceUUID = UUID()
        let database = try Connection(.inMemory)
        try NetworkCache.createTable(db: database)
        let config = Configuration(appGroupIdentifier: nil, sqliteDatabasePath: "", serverURL: URL(string: Self.baseURL())!, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true)
        hashingManager = HashingManager()
        try? hashingManager.add(hashing: DropboxHashing())
        api = ServerAPI(database: database, hashingManager: hashingManager, delegate: self, config: config)
        _ = handlers.user.removeUser()
        XCTAssert(handlers.user.addUser())
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testCreateExistingSharingGroupFails() throws {
        let sharingGroupUUID = try getSharingGroupUUID()
        let exp = expectation(description: "exp")
        api.createSharingGroup(sharingGroup: sharingGroupUUID) { error in
            XCTAssert(error != nil)
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testCreateSharingGroupWithoutNameWorks() throws {
        let newSharingGroupUUID = UUID()
        let exp = expectation(description: "exp")
        api.createSharingGroup(sharingGroup: newSharingGroupUUID) { error in
            XCTAssert(error == nil)
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        guard let index = getIndex(sharingGroupUUID: nil) else {
            XCTFail()
            return
        }
        
        let filter = index.sharingGroups.filter {$0.sharingGroupUUID == newSharingGroupUUID.uuidString}
        guard filter.count == 1 else {
            XCTFail()
            return
        }
    }
    
    func testCreateSharingGroupWithNameWorks() throws {
        let newSharingGroupUUID = UUID()
        let sharingGroupName = "Foobly"
        
        let exp = expectation(description: "exp")
        api.createSharingGroup(sharingGroup: newSharingGroupUUID, sharingGroupName: sharingGroupName) { error in
            XCTAssert(error == nil)
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        guard let index = getIndex(sharingGroupUUID: nil) else {
            XCTFail()
            return
        }
        
        let filter = index.sharingGroups.filter {$0.sharingGroupUUID == newSharingGroupUUID.uuidString}
        guard filter.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(filter[0].sharingGroupName == sharingGroupName)
    }
    
    func testUpdateSharingGroupWithNewUUIDFails() throws {
        let sharingGroupUUID = UUID()
        let newName = "Barfly foofly"
        
        let exp = expectation(description: "exp")
        api.updateSharingGroup(sharingGroup: sharingGroupUUID, newSharingGroupName: newName) { error in
            XCTAssert(error != nil)
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testUpdateSharingGroup() throws {
        let sharingGroupUUID = try getSharingGroupUUID()
        let newName = "Barfly foofly"
        
        let exp = expectation(description: "exp")
        api.updateSharingGroup(sharingGroup: sharingGroupUUID, newSharingGroupName: newName) { error in
            XCTAssert(error == nil)
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        guard let index = getIndex(sharingGroupUUID: nil) else {
            XCTFail()
            return
        }
        
        let filter = index.sharingGroups.filter {$0.sharingGroupUUID == sharingGroupUUID.uuidString}
        guard filter.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(filter[0].sharingGroupName == newName)
    }
}
