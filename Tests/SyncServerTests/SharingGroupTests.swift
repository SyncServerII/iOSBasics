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
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        handlers = DelegateHandlers()
        handlers.user = try dropboxUser()
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
    
    func testRemoveUserFromExistingSharingGroupWorks() throws {
        try self.sync()
        let existingSharingGroupUUID = try getSharingGroupUUID()
        
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
        
        let sharingGroups = try syncServer.sharingGroups()
        let filter = sharingGroups.filter { $0.sharingGroupUUID == existingSharingGroupUUID }
        guard filter.count == 0 else {
            XCTFail("\(filter.count)")
            return
        }
    }
}
