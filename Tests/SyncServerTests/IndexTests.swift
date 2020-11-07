//
//  IndexTests.swift
//  SyncServerTests
//
//  Created by Christopher G Prince on 9/11/20.
//

import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn
import ChangeResolvers
@testable import TestsCommon

class IndexTests: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, Delegate, SyncServerTests {
    var deviceUUID: UUID!
    var hashingManager: HashingManager!
    var api: ServerAPI!
    var syncServer: SyncServer!
    var handlers = DelegateHandlers()
    var database: Connection!
    var config:Configuration!
    var fakeHelper:SignInServicesHelperFake!

    override func setUpWithError() throws {
        try super.setUpWithError()
        set(logLevel: .trace)
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
    }

    func testIndexCalledDirectly() throws {
        let sharingGroupUUID = try getSharingGroupUUID()

        let exp = expectation(description: "exp")
        
        handlers.syncCompleted = { _, result in
            guard case .index(let uuid, let index) = result else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            XCTAssert(sharingGroupUUID == uuid)
            XCTAssert(index.count == 0)
            guard let result = try? SharingEntry.fetchSingleRow(db: self.database, where: SharingEntry.sharingGroupUUIDField.description == sharingGroupUUID) else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            XCTAssert(result.sharingGroupUUID == sharingGroupUUID)
            exp.fulfill()
        }
        
        handlers.error = { _, error in
            XCTFail("\(String(describing: error))")
            exp.fulfill()
        }
        
        syncServer.getIndex(sharingGroupUUID: sharingGroupUUID)

        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testIndexCalledFromSyncServer() throws {
        let sharingGroupUUID = try getSharingGroupUUID()

        let exp = expectation(description: "exp")
        
        handlers.syncCompleted = { _, result in
            guard case .index(let uuid, let index) = result else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            XCTAssert(sharingGroupUUID == uuid)
            XCTAssert(index.count == 0)
            guard let result = try? SharingEntry.fetchSingleRow(db: self.database, where: SharingEntry.sharingGroupUUIDField.description == sharingGroupUUID) else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            XCTAssert(result.sharingGroupUUID == sharingGroupUUID)
            exp.fulfill()
        }
        
        handlers.error = { _, error in
            XCTFail()
            exp.fulfill()
        }
        
        try syncServer.sync(sharingGroupUUID: sharingGroupUUID)

        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testIndexCalledFromSyncServerWithOneFile() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let uploadable = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID)
        
        guard uploadable.uploads.count == 1 else {
            XCTFail()
            return
        }
        let uploadableFile = uploadable.uploads[0]

        let exp = expectation(description: "exp")
        
        handlers.syncCompleted = { _, result in
            guard case .index(let uuid, let index) = result else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            XCTAssert(sharingGroupUUID == uuid)
            guard index.count == 1 else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            XCTAssert(uploadableFile.uuid.uuidString == index[0].fileUUID)
            
            guard let result = try? SharingEntry.fetchSingleRow(db: self.database, where: SharingEntry.sharingGroupUUIDField.description == sharingGroupUUID) else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            XCTAssert(result.sharingGroupUUID == sharingGroupUUID)
            exp.fulfill()
        }
        
        handlers.error = { _, error in
            XCTFail()
            exp.fulfill()
        }
        
        try syncServer.sync(sharingGroupUUID: sharingGroupUUID)

        waitForExpectations(timeout: 10, handler: nil)
    }
    
    #warning("FIXME-- when we have deletions working")
    /*
    func testMakeSureIndexUpdateForDeletedObjectHasDeletionFail() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        let uploadable = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID)
        
        guard uploadable.uploads.count == 1 else {
            XCTFail()
            return
        }
        let uploadableFile = uploadable.uploads[0]
        
        let exp = expectation(description: "exp")
        handlers.deletionCompleted = { _ in
            exp.fulfill()
        }
        
        try syncServer.queue(deletion: declaration)
        waitForExpectations(timeout: 10, handler: nil)
        
        // Reset the database show a state *as if* another client instance had done the upload/deleteion.
        database = try Connection(.inMemory)
        let fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, configuration: config, signIns: fakeSignIns)
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        
        let exp2 = expectation(description: "exp2")
        handlers.syncCompleted = { _,_ in
            exp2.fulfill()
        }
        
        // Fetch the database state again.
        try syncServer.sync(sharingGroupUUID: sharingGroupUUID)
        waitForExpectations(timeout: 10, handler: nil)
        
        // This is as if another client attempts a deletion of a file after a sync where it learned about the deleted file for the first time.
        do {
            try syncServer.queue(deletion: declaration)
        } catch let error {
            guard let syncServerError = error as? SyncServerError else {
                XCTFail()
                return
            }
            
            XCTAssert(syncServerError == SyncServerError.attemptToDeleteAnAlreadyDeletedFile)
            return
        }
        
        XCTFail()
    }
    
    func testMakeSureIndexUpdateForDeletedObjectHasUploadFail() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        let declaration = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID)
        guard declaration.declaredFiles.count == 1,
            let declaredFile = declaration.declaredFiles.first else {
            XCTFail()
            return
        }

        let exp = expectation(description: "exp")
        handlers.deletionCompleted = { _ in
            exp.fulfill()
        }
        
        try syncServer.queue(deletion: declaration)
        waitForExpectations(timeout: 10, handler: nil)
        
        // Reset the database show a state *as if* another client instance had done the upload/deleteion.
        database = try Connection(.inMemory)
        let fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, configuration: config, signIns: fakeSignIns)
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        
        let exp2 = expectation(description: "exp2")
        handlers.syncCompleted = { _,_ in
            exp2.fulfill()
        }
        
        // Fetch the database state again.
        try syncServer.sync(sharingGroupUUID: sharingGroupUUID)
        waitForExpectations(timeout: 10, handler: nil)
        
        let uploadable1 = FileUpload(uuid: declaredFile.uuid, dataSource: .copy(exampleTextFileURL))

        // This is as if another client attempts an upload of a file after a sync where it learned about the deleted file for the first time.
        do {
            try syncServer.queue(uploads: [uploadable1], declaration: declaration)
        } catch let error {
            guard let syncServerError = error as? SyncServerError else {
                XCTFail()
                return
            }
            
            XCTAssert(syncServerError == SyncServerError.attemptToQueueADeletedFile)
            return
        }
        
        XCTFail()
    }
    
    func testMakeSureIndexWithDeletedFileMarksAsDeleted() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        let declaration = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID)
        guard declaration.declaredFiles.count == 1,
            let declaredFile = declaration.declaredFiles.first else {
            XCTFail()
            return
        }

        let exp = expectation(description: "exp")
        handlers.deletionCompleted = { _ in
            exp.fulfill()
        }
        
        try syncServer.queue(deletion: declaration)
        waitForExpectations(timeout: 10, handler: nil)
        
        // Reset the deleted state of the file.
        guard let entry = try DirectoryEntry.fetchSingleRow(db: database, where: DirectoryEntry.fileUUIDField.description == declaredFile.uuid) else {
            XCTFail()
            return
        }
        
        try entry.update(setters:
            DirectoryEntry.deletedLocallyField.description <- false,
            DirectoryEntry.deletedOnServerField.description <- false)
        
        let exp2 = expectation(description: "exp2")
        handlers.syncCompleted = { _,_ in
            exp2.fulfill()
        }
        
        // Fetch the database state again.
        try syncServer.sync(sharingGroupUUID: sharingGroupUUID)
        waitForExpectations(timeout: 10, handler: nil)
        
        // The deleted state of the file should have been updated.
        guard let entry2 = try DirectoryEntry.fetchSingleRow(db: database, where: DirectoryEntry.fileUUIDField.description == declaredFile.uuid) else {
            XCTFail()
            return
        }
        
        XCTAssert(!entry2.deletedLocally)
        XCTAssert(entry2.deletedOnServer)
    }
    */
}
