
import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn
import ChangeResolvers
@testable import TestsCommon

class SharingInvitationTests: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, Delegate, SyncServerTests {
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
        set(logLevel: .trace)
        handlers = DelegateHandlers()
        handlers.user = try dropboxUser()
        user2 = try dropboxUser(selectUser: .second)
        deviceUUID = UUID()
        database = try Connection(.inMemory)
        hashingManager = HashingManager()
        try hashingManager.add(hashing: handlers.user.hashing)
        let serverURL = URL(string: Self.baseURL())!
        config = Configuration(appGroupIdentifier: nil, serverURL: serverURL, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true)
        fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, configuration: config, signIns: fakeSignIns)
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
        syncServer.createSharingInvitation(withPermission: permission, sharingGroupUUID: sharingGroupUUID, numberAcceptors: 2, allowSocialAcceptance: false) { result in
            switch result {
            case .success:
                break
            case .failure:
                XCTFail()
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testGetSharingInvitationInfo() throws {
        let permission:Permission = .write
        let sharingGroupUUID = try getSharingGroupUUID()
        
        var code: UUID!
        
        let exp = expectation(description: "exp")
        syncServer.createSharingInvitation(withPermission: permission, sharingGroupUUID: sharingGroupUUID, numberAcceptors: 2, allowSocialAcceptance: false) { result in
            switch result {
            case .success(let uuid):
                code = uuid
            case .failure:
                XCTFail()
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        let exp2 = expectation(description: "exp")
        syncServer.getSharingInvitationInfo(sharingInvitationUUID: code) { result in
            switch result {
            case .success:
                break
            case .failure:
                XCTFail()
            }
            exp2.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testRedeemSharingInvitation() throws {
        let permission:Permission = .write
        let sharingGroupUUID = try getSharingGroupUUID()
        
        var code: UUID!
        
        let exp = expectation(description: "exp")
        syncServer.createSharingInvitation(withPermission: permission, sharingGroupUUID: sharingGroupUUID, numberAcceptors: 2, allowSocialAcceptance: false) { result in
            switch result {
            case .success(let uuid):
                code = uuid
            case .failure:
                XCTFail()
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        handlers.user = user2
        
        let exp2 = expectation(description: "exp")
        syncServer.redeemSharingInvitation(sharingInvitationUUID: code) { result in
            switch result {
            case .success:
                break
            case .failure:
                XCTFail()
            }
            exp2.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        XCTAssert(user2.removeUser())
    }
}
