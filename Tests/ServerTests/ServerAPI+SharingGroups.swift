
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
    var user2:TestUser!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        handlers = DelegateHandlers()
        user2 = try dropboxUser(selectUser: .second)
        handlers.user = try dropboxUser()
        deviceUUID = UUID()
        let database = try Connection(.inMemory)
        try NetworkCache.createTable(db: database)
        let config = Configuration(appGroupIdentifier: nil, serverURL: URL(string: Self.baseURL())!, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true, deferredCheckInterval: nil)
        hashingManager = HashingManager()
        try? hashingManager.add(hashing: DropboxHashing())
        let serialQueue = DispatchQueue(label: "iOSBasicsTests")
        let backgroundAssertable = MainAppBackgroundTask()
        api = ServerAPI(database: database, hashingManager: hashingManager, delegate: self, serialQueue: serialQueue, backgroundAsssertable: backgroundAssertable, config: config)
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
        
        XCTAssert(filter1[0].deleted == false)
        
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
        // The prior sharing group will still be present.
        guard filter2.count == 1 else {
            XCTFail("filter2.count: \(filter2.count)")
            return
        }
        
        // But it will be marked as deleted.
        XCTAssert(filter2[0].deleted == true)
    }
    
    // Remove one user from a sharing group. While other user remains in the sharing group.
    func testRemoveOneUserFromExistingSharingGroupWorks() throws {        
        // 1) Add first user (with its sharing group)
        // This was done for a dropbox user by initial `setUpWithError`.
        
        // 2) Create a sharing invitation for that sharing group.
        guard let result = getIndex(sharingGroupUUID: nil),
            result.sharingGroups.count > 0,
            let sharingGroupUUIDString = result.sharingGroups[0].sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard let sharingGroupUUID = UUID(uuidString: sharingGroupUUIDString) else {
            XCTFail()
            return
        }
        
        guard let sharingInvitationUUID = createSharingInvitation(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        // 3) Redeem that invitation by second user.
        // Switch over to 2nd user to redeem the invitation.
        let firstUser = handlers.user
        handlers.user = user2
        
        let exp = expectation(description: "exp")
        
        api.redeemSharingInvitation(sharingInvitationUUID: sharingInvitationUUID, cloudFolderName: nil) { result in
        
            switch result {
            case .failure:
                XCTFail()
            case .success(let result):
                XCTAssert(result.userCreated)
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        
        // 4) Remove the second user from the sharing group.

        let exp2 = expectation(description: "exp")
        api.removeFromSharingGroup(sharingGroup: sharingGroupUUID) { error in
            XCTAssert(error == nil)
            exp2.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)

        // For second user: Sharing group should still be returned in an index request. It *should* be marked as deleted.
        guard let index2 = getIndex(sharingGroupUUID: nil) else {
            XCTFail()
            return
        }
        
        let filter2 = index2.sharingGroups.filter {$0.sharingGroupUUID == sharingGroupUUID.uuidString}
        // The prior sharing group will still be present.
        guard filter2.count == 1 else {
            XCTFail("filter2.count: \(filter2.count)")
            return
        }
        
        XCTAssert(filter2[0].deleted == true)
        
        // For first user: Sharing group should still be returned in an index request. It should *not* be marked as deleted.
        handlers.user = firstUser
        
        guard let index3 = getIndex(sharingGroupUUID: nil) else {
            XCTFail()
            return
        }
        
        let filter3 = index3.sharingGroups.filter {$0.sharingGroupUUID == sharingGroupUUID.uuidString}
        // The prior sharing group will still be present.
        guard filter3.count == 1 else {
            XCTFail("filter3.count: \(filter3.count)")
            return
        }
        
        XCTAssert(filter3[0].deleted == false)
        
        // Cleanup
        handlers.user = user2
        XCTAssert(handlers.user.removeUser())
    }
}
