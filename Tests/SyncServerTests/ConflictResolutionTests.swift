//
//  ConflictResolutionTests.swift
//  iOSBasicsTests
//
//  Created by Christopher G Prince on 9/14/20.
//

import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn
import ChangeResolvers
@testable import TestsCommon

class ConflictResolutionTests: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, Delegate, SyncServerTests {
    var deviceUUID: UUID!
    var hashingManager: HashingManager!
    var uploadCompletedHandler: ((Swift.Result<UploadFileResult, Error>) -> ())?
    var downloadCompletedHandler: ((Swift.Result<DownloadFileResult, Error>) -> ())?
    
    var api: ServerAPI!
    var syncServer: SyncServer!

    var database: Connection!
    var config:Configuration!
    var handlers = DelegateHandlers()
    var fakeHelper:SignInServicesHelperFake!
    
    override func setUpWithError() throws {
        handlers = DelegateHandlers()
        try super.setUpWithError()
        handlers.user = try dropboxUser()
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
    }
    
    // https://github.com/SyncServerII/ServerMain/issues/7

    func testDeletionAfterServerDeletionDoesNotFail() throws {
        let fileUUID1 = UUID()
        try self.sync(withSharingGroupUUID: nil)
        let sharingGroupUUID = try getSharingGroupUUID()

        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .copy(exampleTextFileURL), uuid: fileUUID1)
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: [file1])
        
        try syncServer.queue(upload: upload)
        waitForUploadsToComplete(numberUploads: 1)
        
        try syncServer.queue(objectDeletion: upload.fileGroupUUID)

        let exp = expectation(description: "exp")
        handlers.deletionCompleted = { _, _ in
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        // Wait for some period of time for the deferred deletion to complete.
        Thread.sleep(forTimeInterval: 5)

        // This `sync` is to trigger the check for the deferred upload completion.
        try syncServer.sync()

        let exp2 = expectation(description: "exp2")
        handlers.deferredCompleted = { _, operation, fileGroupUUIDs in
            XCTAssert(operation == .deletion)
            XCTAssert(fileGroupUUIDs.count == 1)
            exp2.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        // Now, file is deleted on server. Cheat and mark our directory entry as non-deleted.
        
        guard let fileEntry = try DirectoryFileEntry.fetchSingleRow(db: database, where: DirectoryFileEntry.fileUUIDField.description == fileUUID1) else {
            XCTFail()
            return
        }
        
        guard let objectEntry = try DirectoryObjectEntry.fetchSingleRow(db: database, where: DirectoryObjectEntry.fileGroupUUIDField.description == upload.fileGroupUUID) else {
            XCTFail()
            return
        }
        
        try fileEntry.update(setters:
            DirectoryFileEntry.deletedLocallyField.description <- false,
            DirectoryFileEntry.deletedOnServerField.description <- false)

        try objectEntry.update(setters:
            DirectoryObjectEntry.deletedLocallyField.description <- false,
            DirectoryObjectEntry.deletedOnServerField.description <- false)
            
        let exp3 = expectation(description: "exp")
        handlers.deletionCompleted = { _, _ in
            exp3.fulfill()
        }
        
        // Note that this second delete works "out of the box" despite of the fact that we fooled ourselves (locally) into believing the file was not deleted. The server allows multiple deletions with no ill effect. (The second deletion does nothing).
        try syncServer.queue(objectDeletion: upload.fileGroupUUID)
        waitForExpectations(timeout: 10, handler: nil)
    }

    func testUploadAfterServerDeletionDoesNotFail() throws {
        let fileUUID1 = UUID()
        let fileGroupUUID1 = UUID()
        
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: CommentFile.changeResolverName)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
            
        func object1(v0: Bool) throws {
            let upload:ObjectUpload
            
            if v0 {
                let commentFile = CommentFile()
                let commentFileData = try commentFile.getData()

                let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .data(commentFileData), uuid: fileUUID1)
                upload = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID1, sharingGroupUUID: sharingGroupUUID, uploads: [file1])
            }
            else {
                let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
                
                let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .data(comment.updateContents), uuid: fileUUID1)
                upload = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID1, sharingGroupUUID: sharingGroupUUID, uploads: [file1])
            }

            try syncServer.queue(upload: upload)
        }
        
        try object1(v0: true)
        waitForUploadsToComplete(numberUploads: 1)
        
        // v0 file uploaded.
        
        // Let's delete it.
        
        try syncServer.queue(objectDeletion: fileGroupUUID1)

        let exp = expectation(description: "exp")
        handlers.deletionCompleted = { _, _ in
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        // Wait for some period of time for the deferred deletion to complete.
        Thread.sleep(forTimeInterval: 5)

        // This `sync` is to trigger the check for the deferred upload completion.
        try syncServer.sync()

        let exp2 = expectation(description: "exp2")
        handlers.deferredCompleted = { _, operation, fileGroupUUIDs in
            XCTAssert(operation == .deletion)
            XCTAssert(fileGroupUUIDs.count == 1)
            exp2.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        // Now, file is deleted on server. Cheat and mark our directory entry as non-deleted.
        
        guard let fileEntry = try DirectoryFileEntry.fetchSingleRow(db: database, where: DirectoryFileEntry.fileUUIDField.description == fileUUID1) else {
            XCTFail()
            return
        }
        
        guard let objectEntry = try DirectoryObjectEntry.fetchSingleRow(db: database, where: DirectoryObjectEntry.fileGroupUUIDField.description == fileGroupUUID1) else {
            XCTFail()
            return
        }
        
        try fileEntry.update(setters:
            DirectoryFileEntry.deletedLocallyField.description <- false,
            DirectoryFileEntry.deletedOnServerField.description <- false)

        try objectEntry.update(setters:
            DirectoryObjectEntry.deletedLocallyField.description <- false,
            DirectoryObjectEntry.deletedOnServerField.description <- false)
            
        try object1(v0: false)
        waitForUploadsToComplete(numberUploads: 1, gone: true)
    }
}
