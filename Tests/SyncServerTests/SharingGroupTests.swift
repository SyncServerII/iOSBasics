//
//  SharingGroupTests.swift
//  SyncServerTests
//
//  Created by Christopher G Prince on 9/19/20.
//

import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn
import ChangeResolvers
@testable import TestsCommon

class SharingGroupTests: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, Delegate, SyncServerTests {
    var handlers = DelegateHandlers()
    var deviceUUID: UUID!
    var hashingManager: HashingManager!
    var api: ServerAPI!
    var syncServer: SyncServer!
    var fakeHelper:SignInServicesHelperFake!
    var database: Connection!
    var config:Configuration!
    var user2: TestUser!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        handlers = DelegateHandlers()
        handlers.user = try dropboxUser()
        user2 = try dropboxUser(selectUser: .second)
        deviceUUID = UUID()
        database = try Connection(.inMemory)
        hashingManager = HashingManager()
        try hashingManager.add(hashing: handlers.user.hashing)
        let serverURL = URL(string: Self.baseURL())!
        config = Configuration(appGroupIdentifier: nil, serverURL: serverURL, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true, deferredCheckInterval: nil)
        fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, requestable: FakeRequestable(), configuration: config, signIns: fakeSignIns, backgroundAsssertable: MainAppBackgroundTask(), migrationRunner: MigrationRunnerFake())
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
    
    func testCreateNewSharingGroupWorks() throws {
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
    }
    
    func testCreateExistingSharingGroupFails() throws {
        try self.sync()
        let existingSharingGroupUUID = try getSharingGroupUUID()
    
        let exp = expectation(description: "exp")
        syncServer.createSharingGroup(sharingGroupUUID: existingSharingGroupUUID) { error in
            XCTAssert(error != nil)
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
    }

    func testUpdateNewSharingGroupFails() throws {
        try self.sync()
        let newSharingGroupUUID = UUID()
    
        let exp = expectation(description: "exp")
        syncServer.updateSharingGroup(sharingGroupUUID: newSharingGroupUUID, newSharingGroupName: "Foobly") { error in
            XCTAssert(error != nil)
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testUpdateExistingSharingGroupWorks() throws {
        try self.sync()
        let existingSharingGroupUUID = try getSharingGroupUUID()
        let sharingGroupName = "Foobly"
        
        let exp = expectation(description: "exp")
        let exp2 = expectation(description: "exp")

        handlers.syncCompleted = { _, _ in
            exp2.fulfill()
        }
        
        syncServer.updateSharingGroup(sharingGroupUUID: existingSharingGroupUUID, newSharingGroupName: sharingGroupName) { error in
            XCTAssert(error == nil)
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        let sharingGroups = try syncServer.sharingGroups()
        let filter = sharingGroups.filter { $0.sharingGroupUUID == existingSharingGroupUUID }
        guard filter.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(filter[0].sharingGroupName == sharingGroupName)
    }
    
    func testRemoveUserFromUnknownSharingGroupFails() throws {
        try self.sync()
        let newSharingGroupUUID = UUID()
        
        let exp = expectation(description: "exp")
        
        syncServer.removeFromSharingGroup(sharingGroupUUID: newSharingGroupUUID) { error in
            XCTAssert(error != nil)
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    // This tests if a user is a member of a sharing group where that sharing group has been entirely removed. i.e., because the specific user in question was the only member, when the sharing group is removed, that entirely remove the sharing group.
    func testRemoveUserFromExistingSharingGroupWorks() throws {
        try self.sync()
        let existingSharingGroupUUID = try getSharingGroupUUID()
        
        let sharingGroups1 = try syncServer.sharingGroups()
        let filter1 = sharingGroups1.filter { $0.sharingGroupUUID == existingSharingGroupUUID }
        guard filter1.count == 1 else {
            XCTFail("\(filter1.count)")
            return
        }
        
        XCTAssert(!filter1[0].deleted)
        
        let exp = expectation(description: "exp")
        let exp2 = expectation(description: "exp")

        handlers.syncCompleted = { _, _ in
            exp2.fulfill()
        }
        
        syncServer.removeFromSharingGroup(sharingGroupUUID: existingSharingGroupUUID) { error in
            XCTAssert(error == nil)
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        
        let sharingGroups2 = try syncServer.sharingGroups()
        let filter2 = sharingGroups2.filter { $0.sharingGroupUUID == existingSharingGroupUUID }
        guard filter2.count == 1 else {
            XCTFail("\(filter2.count)")
            return
        }
        
        XCTAssert(filter2[0].deleted)
    }
    
    // Test for membership in a sharing group where that sharing group still exists, but the specific user has been removed.
    func testRemoveUserFromSharingGroupWhereThatSharingGroupStillExistsAfter() throws {
        // 1) Create first user, which also creates a sharing group.
        // Alread done by test setup.
        let sharingGroupUUID = try getSharingGroupUUID()
        
        // 2) Add second user to that sharing group.
        let permission:Permission = .write
        
        var sharingInvitation: UUID!
        
        let exp = expectation(description: "exp")
        syncServer.createSharingInvitation(withPermission: permission, sharingGroupUUID: sharingGroupUUID, numberAcceptors: 1, allowSocialAcceptance: false) { result in
            switch result {
            case .success(let uuid):
                sharingInvitation = uuid
                
            case .failure:
                XCTFail()
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        guard sharingInvitation != nil else {
            XCTFail()
            return
        }
        
        // Reset the database. So we can switch to another user.
        let firstUser = handlers.user
        handlers.user = user2
        
        database = try Connection(.inMemory)
        let fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, requestable: FakeRequestable(), configuration: config, signIns: fakeSignIns, backgroundAsssertable: MainAppBackgroundTask(), migrationRunner: MigrationRunnerFake())
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        syncServer.helperDelegate = self
        handlers.objectType = { _, _ in
            return nil
        }
        
        let exp2 = expectation(description: "exp")

        handlers.syncCompleted = { _, _ in
            exp2.fulfill()
        }
        
        let exp3 = expectation(description: "exp")
        syncServer.redeemSharingInvitation(sharingInvitationUUID: sharingInvitation) { result in
            switch result {
            case .success:
                break
            case .failure:
                XCTFail()
            }
            exp3.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        
        // 3) Remove that second user from the sharing group.
        let exp4 = expectation(description: "exp")
        let exp5 = expectation(description: "exp")

        handlers.syncCompleted = { _, _ in
            exp4.fulfill()
        }
        
        syncServer.removeFromSharingGroup(sharingGroupUUID: sharingGroupUUID) { error in
            XCTAssert(error == nil, "\(String(describing: error))")
            exp5.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        
        // 4) Check for membership by first and second user. Only first should still be in the sharing group.
        
        // Second
        let sharingGroups = try syncServer.sharingGroups()
        let filter = sharingGroups.filter { $0.sharingGroupUUID == sharingGroupUUID }
        guard filter.count == 1 else {
            XCTFail("\(filter.count)")
            return
        }
        
        XCTAssert(filter[0].deleted)
        
        // Switch back to first user
        handlers.user = firstUser

        database = try Connection(.inMemory)
        let fakeHelper2 = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns2 = SignIns(signInServicesHelper: fakeHelper2)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, requestable: FakeRequestable(), configuration: config, signIns: fakeSignIns2, backgroundAsssertable: MainAppBackgroundTask(), migrationRunner: MigrationRunnerFake())
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        syncServer.helperDelegate = self
        handlers.objectType = { _, _ in
            return nil
        }

        let exp6 = expectation(description: "exp")

        handlers.syncCompleted = { _, _ in
            exp6.fulfill()
        }
        
        try syncServer.sync()
        
        waitForExpectations(timeout: 10, handler: nil)
        
        let sharingGroups2 = try syncServer.sharingGroups()
        let filter2 = sharingGroups2.filter { $0.sharingGroupUUID == sharingGroupUUID }
        guard filter2.count == 1 else {
            XCTFail("\(filter2.count)")
            return
        }
        
        XCTAssert(!filter2[0].deleted)
        
        // Cleanup
        XCTAssert(user2.removeUser())
    }
}
