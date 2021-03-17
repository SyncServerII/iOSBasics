
import XCTest
@testable import iOSBasics
import iOSSignIn
@testable import iOSDropbox
import ServerShared
import iOSShared
import SQLite
@testable import TestsCommon

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
        let config = Configuration(appGroupIdentifier: nil, serverURL: URL(string: Self.baseURL())!, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true)
        hashingManager = HashingManager()
        try? hashingManager.add(hashing: DropboxHashing())
        let serialQueue = DispatchQueue(label: "iOSBasicsTests")
        api = ServerAPI(database: database, hashingManager: hashingManager, delegate: self, serialQueue: serialQueue, config: config)
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
    
    func testUpdateSharingGroupWithFakeUUIDFails() throws {
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
    
    func testRemoveUserFromUnknownSharingGroupFails() throws {
        let unknownSharingGroup = UUID()
        
        let exp = expectation(description: "exp")
        api.removeFromSharingGroup(sharingGroup: unknownSharingGroup) { error in
            XCTAssert(error != nil)
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testRemoveUserFromExistingSharingGroupWorks() throws {
        let sharingGroupUUID = try getSharingGroupUUID()

        guard let index1 = getIndex(sharingGroupUUID: nil) else {
            XCTFail()
            return
        }
        
        let filter1 = index1.sharingGroups.filter {$0.sharingGroupUUID == sharingGroupUUID.uuidString}
        guard filter1.count == 1 else {
            XCTFail()
            return
        }
        
        let exp = expectation(description: "exp")
        api.removeFromSharingGroup(sharingGroup: sharingGroupUUID) { error in
            XCTAssert(error == nil)
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        guard let index2 = getIndex(sharingGroupUUID: nil) else {
            XCTFail()
            return
        }
        
        let filter2 = index2.sharingGroups.filter {$0.sharingGroupUUID == sharingGroupUUID.uuidString}
        guard filter2.count == 0 else {
            XCTFail()
            return
        }
    }
}
