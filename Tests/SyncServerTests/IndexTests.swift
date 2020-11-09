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
        
        syncServer.helperDelegate = self
        handlers.objectType = { _, _ in
            return nil
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
        
        let (uploadable, _) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID)
        
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
    
    func testMakeSureIndexUpdateForDeletedObjectHasDeletionFail() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        let (uploadable, example) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID)
        
        guard uploadable.uploads.count == 1 else {
            XCTFail()
            return
        }
        //let uploadableFile = uploadable.uploads[0]
        
        let exp = expectation(description: "exp")
        handlers.deletionCompleted = { _ in
            exp.fulfill()
        }
        
        try syncServer.queue(objectDeletion: uploadable.fileGroupUUID)
        waitForExpectations(timeout: 10, handler: nil)
        
        // Reset the database show a state *as if* another client instance had done the upload/deleteion.
        database = try Connection(.inMemory)
        let fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, configuration: config, signIns: fakeSignIns)
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        syncServer.helperDelegate = self
        
        try syncServer.register(object: example)

        let exp2 = expectation(description: "exp2")
        handlers.syncCompleted = { _,_ in
            exp2.fulfill()
        }
        
        // Fetch the database state again.
        try syncServer.sync(sharingGroupUUID: sharingGroupUUID)
        waitForExpectations(timeout: 10, handler: nil)
        
        // This is as if another client attempts a deletion of a file after a sync where it learned about the deleted file for the first time.
        do {
            try syncServer.queue(objectDeletion: uploadable.fileGroupUUID)
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

        let (objectUpload, example) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID)
        guard objectUpload.uploads.count == 1,
            let uploadFile = objectUpload.uploads.first else {
            XCTFail()
            return
        }

        let exp = expectation(description: "exp")
        handlers.deletionCompleted = { _ in
            exp.fulfill()
        }
        
        try syncServer.queue(objectDeletion: objectUpload.fileGroupUUID)
        waitForExpectations(timeout: 10, handler: nil)
        
        // Reset the database show a state *as if* another client instance had done the upload/deleteion.
        database = try Connection(.inMemory)
        let fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, configuration: config, signIns: fakeSignIns)
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        syncServer.helperDelegate = self
        
        try syncServer.register(object: example)

        let exp2 = expectation(description: "exp2")
        handlers.syncCompleted = { _,_ in
            exp2.fulfill()
        }
        
        // Fetch the database state again.
        try syncServer.sync(sharingGroupUUID: sharingGroupUUID)
        waitForExpectations(timeout: 10, handler: nil)
        
        let fileUpload1 = FileUpload(fileLabel: uploadFile.fileLabel, dataSource: .copy(exampleTextFileURL), uuid: uploadFile.uuid)
        let upload = ObjectUpload(objectType: objectUpload.objectType, fileGroupUUID: objectUpload.fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload1])

        // This is as if another client attempts an upload of a file after a sync where it learned about the deleted file for the first time.
        do {
            try syncServer.queue(upload: upload)
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

        let (objectUpload, _) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID)
        guard objectUpload.uploads.count == 1,
            let uploadFile = objectUpload.uploads.first else {
            XCTFail()
            return
        }

        let exp = expectation(description: "exp")
        handlers.deletionCompleted = { _ in
            exp.fulfill()
        }
        
        try syncServer.queue(objectDeletion: objectUpload.fileGroupUUID)
        waitForExpectations(timeout: 10, handler: nil)
        
        // Reset the deleted state of the file.
        guard let fileEntry = try DirectoryFileEntry.fetchSingleRow(db: database, where: DirectoryFileEntry.fileUUIDField.description == uploadFile.uuid) else {
            XCTFail()
            return
        }
            
        guard let objectEntry = try DirectoryObjectEntry.fetchSingleRow(db: database, where: DirectoryObjectEntry.fileGroupUUIDField.description == objectUpload.fileGroupUUID) else {
            XCTFail()
            return
        }

        try fileEntry.update(setters:
            DirectoryFileEntry.deletedLocallyField.description <- false,
            DirectoryFileEntry.deletedOnServerField.description <- false)
            
        try objectEntry.update(setters:
            DirectoryObjectEntry.deletedLocallyField.description <- false,
            DirectoryObjectEntry.deletedOnServerField.description <- false)
        
        let exp2 = expectation(description: "exp2")
        handlers.syncCompleted = { _,_ in
            exp2.fulfill()
        }
        
        // Fetch the database state again.
        try syncServer.sync(sharingGroupUUID: sharingGroupUUID)
        waitForExpectations(timeout: 10, handler: nil)
        
        // The deleted state of the file should have been updated.
        guard let fileEntry2 = try DirectoryFileEntry.fetchSingleRow(db: database, where: DirectoryFileEntry.fileUUIDField.description == uploadFile.uuid) else {
            XCTFail()
            return
        }
            
        guard let objectEntry2 = try DirectoryObjectEntry.fetchSingleRow(db: database, where: DirectoryObjectEntry.fileGroupUUIDField.description == objectUpload.fileGroupUUID) else {
            XCTFail()
            return
        }
        
        XCTAssert(!fileEntry2.deletedLocally)
        XCTAssert(fileEntry2.deletedOnServer)
        XCTAssert(!objectEntry2.deletedLocally)
        XCTAssert(objectEntry2.deletedOnServer)
    }
}
