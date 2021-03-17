
import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn
import ChangeResolvers
@testable import TestsCommon

// Intended for use in creating sharing invitations for use in Neebla

class SharingInvitationTests2: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, Delegate, SyncServerTests {
    var handlers = DelegateHandlers()
    var deviceUUID: UUID!
    var hashingManager: HashingManager!
    var api: ServerAPI!
    var syncServer: SyncServer!
    var database: Connection!
    var config:Configuration!
    var user2: TestUser!
    var fakeHelper:SignInServicesHelperFake!

    override func setUpWithError() throws {
        try super.setUpWithError()
        handlers = DelegateHandlers()
        handlers.user = try dropboxUser(selectUser: .second)
        deviceUUID = UUID()
        database = try Connection(.inMemory)
        hashingManager = HashingManager()
        try hashingManager.add(hashing: handlers.user.hashing)
        let serverURL = URL(string: Self.baseURL())!
        config = Configuration(appGroupIdentifier: nil, serverURL: serverURL, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true)
        fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, requestable: FakeRequestable(), configuration: config, signIns: fakeSignIns)
        api = syncServer.api
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        
        _ = handlers.user.removeUser()
        guard handlers.user.addUser() else {
            throw SyncServerError.internalError("Could not add user")
        }
        
        // So as to not throw an error in `contentsOfDirectory`
        try Files.createDirectoryIfNeeded(config.temporaryFiles.directory)
        
        let filePaths = try FileManager.default.contentsOfDirectory(atPath: config.temporaryFiles.directory.path)
        for filePath in filePaths {
            let url = config.temporaryFiles.directory.appendingPathComponent(filePath)
            try FileManager.default.removeItem(at: url)
        }
        
        syncServer.helperDelegate = self
        handlers.objectType = { _, _ in
            return nil
        }
    }

    override func tearDownWithError() throws {
        // All temporary files should have been removed prior to end of test.
        let filePaths = try FileManager.default.contentsOfDirectory(atPath: config.temporaryFiles.directory.path)
        XCTAssert(filePaths.count == 0, "\(filePaths.count)")
        
        let count = try NetworkCache.numberRows(db: database)
        XCTAssert(count == 0, "\(count)")
    }

    func testCreateSharingInvitation() throws {
        let permission:Permission = .write
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let exp = expectation(description: "exp")
        syncServer.createSharingInvitation(withPermission: permission, sharingGroupUUID: sharingGroupUUID, numberAcceptors: 1, allowSocialAcceptance: false) { result in
            switch result {
            case .success(let invitation):
                logger.info("new invitation code: \(invitation)")
            case .failure:
                XCTFail()
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testCreateNewSharingGroupAndShareWorks() throws {
        try self.sync()
        let newSharingGroupUUID = UUID()
    
        let exp = expectation(description: "exp")
        let exp2 = expectation(description: "exp")

        handlers.syncCompleted = { _, _ in
            exp2.fulfill()
        }
        
        syncServer.createSharingGroup(sharingGroupUUID: newSharingGroupUUID) { error in
            XCTAssert(error == nil)
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        let sharingGroups = try syncServer.sharingGroups()
        let filter = sharingGroups.filter { $0.sharingGroupUUID == newSharingGroupUUID}
        XCTAssert(filter.count == 1)
        
        let permission:Permission = .write
        
        let exp3 = expectation(description: "exp")
        syncServer.createSharingInvitation(withPermission: permission, sharingGroupUUID: newSharingGroupUUID, numberAcceptors: 1, allowSocialAcceptance: false) { result in
            switch result {
            case .success(let invitation):
                logger.info("new invitation code: \(invitation)")
            case .failure:
                XCTFail()
            }
            exp3.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
    }
}
