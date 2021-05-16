//
//  UploadRetryTests.swift
//  SyncServerTests
//
//  Created by Christopher G Prince on 3/31/21.
//

import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn
@testable import TestsCommon
import ChangeResolvers

class UploadRetryTests: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, Delegate, SyncServerTests {
    var deviceUUID: UUID!
    var hashingManager: HashingManager!
    var api: ServerAPI!
    var syncServer: SyncServer!
    var handlers = DelegateHandlers()
    var database: Connection!
    var config:Configuration!
    var fakeHelper:SignInServicesHelperFake!
    var networkRequestable:NetworkRequestable!
    var disableNetwork = false
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        handlers = DelegateHandlers()
        handlers.user = try dropboxUser()
        deviceUUID = UUID()
        database = try Connection(.inMemory)
        hashingManager = HashingManager()
        try hashingManager.add(hashing: handlers.user.hashing)
        let serverURL = URL(string: Self.baseURL())!
        config = Configuration(appGroupIdentifier: nil, serverURL: serverURL, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true, deferredCheckInterval: nil)
        fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        networkRequestable = GatableFakeRequestable() {
            return self.disableNetwork
        }
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, requestable: networkRequestable, configuration: config, signIns: fakeSignIns, backgroundAsssertable: MainAppBackgroundTask(), migrationRunner: MigrationRunnerFake())
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
    
    // On "v0 contents for change resolver (CommentFile) were not valid", another way this could happen is explained here: https://github.com/SyncServerII/Neebla/issues/8#issuecomment-808833536
    // To repro this, I need to start the first upload, but somehow have it fail, then start both uploads together.
    func testV0ContentsNotValidHypothesis2() throws {
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()

        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let changeResolver = CommentFile.changeResolverName
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file2", mimeTypes: [.text], changeResolverName: changeResolver)
        let fileDeclaration2 = FileDeclaration(fileLabel: "file1", mimeTypes: [.jpeg], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1, fileDeclaration2])
        try syncServer.register(object: example)
        
        let commentFile = CommentFile()
        let commentFileData = try commentFile.getData()
                
        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .data(commentFileData), uuid: fileUUID1)
        let file2 = FileUpload(fileLabel: fileDeclaration2.fileLabel, dataSource: .copy(exampleImageFileURL), uuid: fileUUID2)
        let uploads = [file1, file2]
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: uploads)

        disableNetwork = true
        try syncServer.queue(upload: upload)
        disableNetwork = false

        let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        
        let file3 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .data(comment.updateContents), uuid: fileUUID1)
        let uploads2 = [file3]
        
        let upload2 = ObjectUpload(objectType: objectType, fileGroupUUID: upload.fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: uploads2)
        
        try syncServer.queue(upload: upload2)
        
        // Simulate the sync that would happen after adding the comment.
        try syncServer.sync()
        
        waitForUploadsToComplete(numberUploads: 2, v0Upload: true)

        // Sync to upload v1 of comment.
        try syncServer.sync()
        
        // Wait for some period of time for the deferred upload to complete.
        Thread.sleep(forTimeInterval: 5)

        // This `sync` is to trigger the check for the deferred upload completion.
        try syncServer.sync()
        
        let exp3 = expectation(description: "exp2")
        handlers.deferredCompleted = { _, operation, count in
            exp3.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testQueueFailsForOneFile() throws {
        let fileUUID1 = UUID()

        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let changeResolver = CommentFile.changeResolverName
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file2", mimeTypes: [.text], changeResolverName: changeResolver)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let commentFile = CommentFile()
        let commentFileData = try commentFile.getData()
                
        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .data(commentFileData), uuid: fileUUID1)
        let uploads = [file1]
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: uploads)

        disableNetwork = true
        try syncServer.queue(upload: upload)
        disableNetwork = false
                
        // Simulate the sync that would happen after adding the comment.
        try syncServer.sync()
        
        waitForUploadsToComplete(numberUploads: 1, v0Upload: true)
    }
    
    func testQueueFailsForOneFileAndFirstSyncFails() throws {
        let fileUUID1 = UUID()

        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let changeResolver = CommentFile.changeResolverName
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file2", mimeTypes: [.text], changeResolverName: changeResolver)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let commentFile = CommentFile()
        let commentFileData = try commentFile.getData()
                
        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .data(commentFileData), uuid: fileUUID1)
        let uploads = [file1]
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: uploads)

        disableNetwork = true
        
        try syncServer.queue(upload: upload)
                
        // Simulate the sync that would happen after adding the comment.
        do {
            try syncServer.sync()
        } catch let error {
            guard let error = error as? SyncServerError,
                error == .networkNotReachable else {
                XCTFail()
                return
            }
        }
        
        disableNetwork = false

        try syncServer.sync()
        
        waitForUploadsToComplete(numberUploads: 1, v0Upload: true)
    }
    
    func testInitialV1UploadFails() throws {
        let fileUUID1 = UUID()

        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let changeResolver = CommentFile.changeResolverName
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file2", mimeTypes: [.text], changeResolverName: changeResolver)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let commentFile = CommentFile()
        let commentFileData = try commentFile.getData()
                
        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .data(commentFileData), uuid: fileUUID1)
        let uploads = [file1]
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: uploads)
        
        try syncServer.queue(upload: upload)
        waitForUploadsToComplete(numberUploads: 1, v0Upload: true)
        
        let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        
        let file3 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .data(comment.updateContents), uuid: fileUUID1)
        let uploads2 = [file3]
        
        let upload2 = ObjectUpload(objectType: objectType, fileGroupUUID: upload.fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: uploads2)
        
        disableNetwork = true
        try syncServer.queue(upload: upload2)
        disableNetwork = false

        // Sync to upload v1 of comment.
        try syncServer.sync()
        
        // Wait for some period of time for the deferred upload to complete.
        Thread.sleep(forTimeInterval: 5)

        // This `sync` is to trigger the check for the deferred upload completion.
        try syncServer.sync()
        
        let exp3 = expectation(description: "exp2")
        handlers.deferredCompleted = { _, operation, count in
            exp3.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testInitialV1UploadFailsAndInitialSyncFails() throws {
        let fileUUID1 = UUID()

        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let changeResolver = CommentFile.changeResolverName
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file2", mimeTypes: [.text], changeResolverName: changeResolver)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let commentFile = CommentFile()
        let commentFileData = try commentFile.getData()
                
        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .data(commentFileData), uuid: fileUUID1)
        let uploads = [file1]
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: uploads)
        
        try syncServer.queue(upload: upload)
        waitForUploadsToComplete(numberUploads: 1, v0Upload: true)
        
        let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        
        let file3 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .data(comment.updateContents), uuid: fileUUID1)
        let uploads2 = [file3]
        
        let upload2 = ObjectUpload(objectType: objectType, fileGroupUUID: upload.fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: uploads2)
        
        disableNetwork = true
        try syncServer.queue(upload: upload2)

        // Simulate the sync that would happen after adding the comment.
        do {
            try syncServer.sync()
        } catch let error {
            guard let error = error as? SyncServerError,
                error == .networkNotReachable else {
                XCTFail()
                return
            }
        }

        disableNetwork = false

        // Sync to upload v1 of comment.
        try syncServer.sync()
        
        // Wait for some period of time for the deferred upload to complete.
        Thread.sleep(forTimeInterval: 5)

        // This `sync` is to trigger the check for the deferred upload completion.
        try syncServer.sync()
        
        let exp3 = expectation(description: "exp2")
        handlers.deferredCompleted = { _, operation, count in
            exp3.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
    }
}
