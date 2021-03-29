//
//  UploadQueue_SyncTests.swift
//  iOSBasicsTests
//
//  Created by Christopher G Prince on 9/6/20.
//

import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn
import ChangeResolvers
@testable import TestsCommon
import FileLogging
import Logging

class UploadQueueTests_Sync: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, Delegate, SyncServerTests {
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
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, requestable: FakeRequestable(), configuration: config, signIns: fakeSignIns, backgroundAsssertable: MainAppBackgroundTask())
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
    
    // Since this uploads a vN file, it *must* use a change resolver.
    func testQueueObjectAlreadyRegisteredWorks() throws {
        let fileUUID1 = UUID()
        let fileGroupUUID1 = UUID()
        
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.jpeg], changeResolverName: CommentFile.changeResolverName)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
            
        func object1(v0: Bool) throws {
            let upload:ObjectUpload
            
            if v0 {
                let commentFile = CommentFile()
                let commentFileData = try commentFile.getData()

                let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .data(commentFileData), uuid: fileUUID1)
                upload = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID1, sharingGroupUUID: sharingGroupUUID, uploads: [file1])
            }
            else {
                let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
                let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .data(comment.updateContents), uuid: fileUUID1)
                upload = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID1, sharingGroupUUID: sharingGroupUUID, uploads: [file1])
            }

            try syncServer.queue(upload: upload)
        }
        
        var count = 0
        handlers.extras.uploadQueued = { _ in
            count += 1
        }
        
        try object1(v0: true)
        
        // This second one should work also-- but not trigger an upload-- because its for the same file group as the immediately prior `queue`. i.e., the active upload.
        try object1(v0: false)
        
        let objectCount = try DeclaredObjectModel.numberRows(db: database,
            where: DeclaredObjectModel.objectTypeField.description == objectType)
        XCTAssert(objectCount == 1)

        waitForUploadsToComplete(numberUploads: 1)
        XCTAssert(count == 1)

        // Trigger the second upload instance.
        try syncServer.sync()
        waitForUploadsToComplete(numberUploads: 1, v0Upload: false)

        // Wait for some period of time for the deferred upload to complete.
        Thread.sleep(forTimeInterval: 5)

        // This `sync` is to trigger the check for the deferred upload completion.
        try syncServer.sync()

        let exp2 = expectation(description: "exp")
        handlers.deferredCompleted = { _, operation, count in
            exp2.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)

        XCTAssert(try UploadFileTracker.numberRows(db: database) == 0)
        XCTAssert(try UploadObjectTracker.numberRows(db: database) == 0)
        XCTAssert(try DirectoryFileEntry.numberRows(db: database) == 1)
        XCTAssert(try DirectoryObjectEntry.numberRows(db: database) == 1)
    }
    
    func testUploadFileAfterInitialQueueOtherDeclaredFile() throws {
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()
        let fileGroupUUID = UUID()
        
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let fileDeclaration2 = FileDeclaration(fileLabel: "file2", mimeTypes: [.text], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1, fileDeclaration2])
        try syncServer.register(object: example)

        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .copy(exampleTextFileURL), uuid: fileUUID1)
        let upload1 = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: [file1])

        try syncServer.queue(upload: upload1)

        let file2 = FileUpload(fileLabel: fileDeclaration2.fileLabel, dataSource: .copy(exampleTextFileURL), uuid: fileUUID2)
        let upload2 = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: [file2])
        
        try syncServer.queue(upload: upload2)
        
        // Wait for 1st upload to complete.
        waitForUploadsToComplete(numberUploads: 1)
        
        // Need to trigger second upload
        try syncServer.sync()
        
        // Wait for 2nd upload to complete.
        waitForUploadsToComplete(numberUploads: 1)
        
        XCTAssert(try UploadFileTracker.numberRows(db: database) == 0)
        XCTAssert(try UploadObjectTracker.numberRows(db: database) == 0)
        XCTAssert(try DirectoryFileEntry.numberRows(db: database) == 2)
        XCTAssert(try DirectoryObjectEntry.numberRows(db: database) == 1)
    }

    func runQueueObject(fileHasBeenDeleted: Bool) throws {
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
                let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .data(commentFileData), uuid: fileUUID1)
                upload = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID1, sharingGroupUUID: sharingGroupUUID, uploads: [file1])
            }
            else {
                let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
                let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .data(comment.updateContents), uuid: fileUUID1)
                upload = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID1, sharingGroupUUID: sharingGroupUUID, uploads: [file1])
            }

            try syncServer.queue(upload: upload)
        }
        
        var count = 0
        handlers.extras.uploadQueued = { _ in
            count += 1
        }
        
        try object1(v0: true)
        
        if fileHasBeenDeleted {
            guard let fileEntry = try DirectoryFileEntry.fetchSingleRow(db: database, where: fileUUID1 == DirectoryFileEntry.fileUUIDField.description) else {
                throw DatabaseError.noObject
            }
            
            try fileEntry.update(setters:
                DirectoryFileEntry.deletedLocallyField.description <- true
            )
            
            guard let objectEntry = try DirectoryObjectEntry.fetchSingleRow(db: database, where: fileGroupUUID1 == DirectoryObjectEntry.fileGroupUUIDField.description) else {
                throw DatabaseError.noObject
            }
            
            try objectEntry.update(setters:
                DirectoryObjectEntry.deletedLocallyField.description <- true
            )
        }
        
        // This second one should work also-- but not trigger an upload-- because its for the same file group as the immediately prior `queue`. i.e., the active upload.
        do {
            try object1(v0: false)
        } catch {
            if fileHasBeenDeleted {
                waitForUploadsToComplete(numberUploads: 1)
                return
            }
            XCTFail()
            return
        }
        
        if fileHasBeenDeleted {
            XCTFail()
            return
        }
        
        let objectCount = try DeclaredObjectModel.numberRows(db: database,
            where: objectType == DeclaredObjectModel.objectTypeField.description)
        XCTAssert(objectCount == 1)
        
        let fileCount = try DirectoryFileEntry.numberRows(db: database, where: fileUUID1 == DirectoryFileEntry.fileUUIDField.description)
        XCTAssert(fileCount == 1, "\(fileCount)")

        waitForUploadsToComplete(numberUploads: 1)
        XCTAssert(count == 1)

        // Trigger the second upload instance.
        try syncServer.sync()
        waitForUploadsToComplete(numberUploads: 1, v0Upload: false)

        // Wait for some period of time for the deferred upload to complete.
        Thread.sleep(forTimeInterval: 5)

        // This `sync` is to trigger the check for the deferred upload completion.
        try syncServer.sync()

        let exp2 = expectation(description: "exp")
        handlers.deferredCompleted = { _, operation, count in
            exp2.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)

        XCTAssert(try UploadFileTracker.numberRows(db: database) == 0)
        XCTAssert(try UploadObjectTracker.numberRows(db: database) == 0)
        XCTAssert(try DirectoryFileEntry.numberRows(db: database) == 1)
        XCTAssert(try DirectoryObjectEntry.numberRows(db: database) == 1)
    }
    
    func testRunQueueObjectFileHasBeenDeletedFails() throws {
        try runQueueObject(fileHasBeenDeleted: true)
    }
    
    func testRunQueueObjectFileHasNotBeenDeletedWorks() throws {
        try runQueueObject(fileHasBeenDeleted: false)
    }
    
    // Sync with two uploads pending of the same file group doesn't trigger both.
    func testQueueTwoObjectsAlreadyRegisteredWorks() throws {
        let fileUUID1 = UUID()
        let fileGroupUUID1 = UUID()
        
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: CommentFile.changeResolverName)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
            
        func object1(v0: Bool, v1Id: UUID = Foundation.UUID()) throws {
            let upload:ObjectUpload
            
            if v0 {
                let commentFile = CommentFile()
                let commentFileData = try commentFile.getData()
                let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .data(commentFileData), uuid: fileUUID1)
                upload = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID1, sharingGroupUUID: sharingGroupUUID, uploads: [file1])
            }
            else {
                let comment = ExampleComment(messageString: "Example", id: v1Id.uuidString)
                let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .data(comment.updateContents), uuid: fileUUID1)
                upload = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID1, sharingGroupUUID: sharingGroupUUID, uploads: [file1])
            }

            try syncServer.queue(upload: upload)
        }
        
        var count = 0
        handlers.extras.uploadQueued = { _ in
            count += 1
        }
        
        try object1(v0: true)
        
        // This two should also work -- but not trigger uploads-- because they are for the same file group as the immediately prior `queue`. i.e., the active upload.
        try object1(v0: false, v1Id: Foundation.UUID())
        try object1(v0: false, v1Id: Foundation.UUID())

        let objectCount = try DeclaredObjectModel.numberRows(db: database,
            where: objectType == DeclaredObjectModel.objectTypeField.description)
        XCTAssert(objectCount == 1)
        
        let fileCount = try DirectoryFileEntry.numberRows(db: database, where: fileUUID1 == DirectoryFileEntry.fileUUIDField.description)
        XCTAssert(fileCount == 1)

        // Wait for the v0 upload
        waitForUploadsToComplete(numberUploads: 1)
        XCTAssert(count == 2)
        
        // Trigger the second upload. i.e., the 1st vN upload
        try syncServer.sync()
        waitForUploadsToComplete(numberUploads: 1, v0Upload: false)

        // Wait for some period of time for the deferred upload to complete.
        Thread.sleep(forTimeInterval: 5)

        // This `sync` will trigger both the check for the 1st deferred upload completion and the third upload. (The 2nd vN upload)
        try syncServer.sync()
        
        let deferredExp1 = expectation(description: "deferredExp1")
        handlers.deferredCompleted = { _, operation, count in
            deferredExp1.fulfill()
        }
        // Piggy backing on the expectation wait in the `waitForUploadsToComplete` for deferredExp1
        
        waitForUploadsToComplete(numberUploads: 1, v0Upload: false)
        
        // Wait for some period of time for the 2nd deferred upload to complete.
        Thread.sleep(forTimeInterval: 5)

        // Check on the 2nd deferred upload.
        try syncServer.sync()
        
        let deferredExp2 = expectation(description: "deferredExp2")
        handlers.deferredCompleted = { _, operation, count in
            deferredExp2.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)

        let fileTrackersCount = try UploadFileTracker.numberRows(db: database)
        XCTAssert(fileTrackersCount == 0, "\(fileTrackersCount)")
        
        let objecTrackersCount = try UploadObjectTracker.numberRows(db: database)
        XCTAssert(objecTrackersCount == 0, "\(objecTrackersCount)")
        
        XCTAssert(try DirectoryFileEntry.numberRows(db: database) == 1)
        XCTAssert(try DirectoryObjectEntry.numberRows(db: database) == 1)
    }
    
    func testVNAndV0UploadFails() throws {
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()
        let fileGroupUUID1 = UUID()
        
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        let commentFile = CommentFile()
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: CommentFile.changeResolverName)
        let fileDeclaration2 = FileDeclaration(fileLabel: "file2", mimeTypes: [.text], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1, fileDeclaration2])
        try syncServer.register(object: example)
        
        // v0 upload for fileUUID1
        let commentFileData = try commentFile.getData()
        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .data(commentFileData), uuid: fileUUID1)
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID1, sharingGroupUUID: sharingGroupUUID, uploads: [file1])
        try syncServer.queue(upload: upload)
        waitForUploadsToComplete(numberUploads: 1)
                
        // vN + v0 upload attempt
        let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        
        // v1
        let file1v1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .data(comment.updateContents), uuid: fileUUID1)
        
        // v0
        let file2v0 = FileUpload(fileLabel: fileDeclaration2.fileLabel, dataSource: .copy(exampleTextFileURL), uuid: fileUUID2)

        let upload2 = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID1, sharingGroupUUID: sharingGroupUUID, uploads: [file1v1, file2v0])

        // Fails because we're not allowing uploads of v0 and vN together within the same `queue` for the same file group.
        do {
            try syncServer.queue(upload: upload2)
        } catch let error {
            guard let syncServerError = error as? SyncServerError,
                syncServerError == SyncServerError.someUploadFilesV0SomeVN else {
                XCTFail()
                return
            }

            return
        }
        
        XCTFail()
    }
}
