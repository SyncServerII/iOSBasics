//
//  DeleteTests.swift
//  SyncServerTests
//
//  Created by Christopher G Prince on 9/13/20.
//

import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn
import ChangeResolvers
@testable import TestsCommon

class DeleteTests: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, Delegate, SyncServerTests {
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
        // Running into `tooManyRequests` HTTP response, so switched from Dropbox to Google for these tests.
        //handlers.user = try googleUser()
        
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
    }

    override func tearDownWithError() throws {
        // All temporary files should have been removed prior to end of test.
        let filePaths = try FileManager.default.contentsOfDirectory(atPath: config.temporaryFiles.directory.path)
        XCTAssert(filePaths.count == 0, "\(filePaths.count)")
        
        let count = try NetworkCache.numberRows(db: database)
        XCTAssert(count == 0, "\(count)")
    }

    func testDeletionWithUnknownDeclaredObjectFails() throws {
        do {
            try syncServer.queue(objectDeletion: UUID())
        } catch let error {
            guard let error = error as? SyncServerError else {
                XCTFail()
                return
            }
            
            XCTAssert(error == .noObject)
            return
        }
        XCTFail()
    }

    func runDeletion(withKnownFileGroupUUID: Bool) throws {
        let fileUUID1 = UUID()
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let fileUpload1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .copy(exampleTextFileURL), uuid: fileUUID1)
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload1])
        
        try syncServer.queue(upload: upload)
        waitForUploadsToComplete(numberUploads: 1)

        let deleteFileGroupUUID: UUID
        if withKnownFileGroupUUID {
            deleteFileGroupUUID = upload.fileGroupUUID
        }
        else {
            deleteFileGroupUUID = UUID()
        }
        
        do {
            try syncServer.queue(objectDeletion: deleteFileGroupUUID)
        } catch let error {
            if withKnownFileGroupUUID {
                XCTFail("\(error)")
            }
            return
        }
        
        if !withKnownFileGroupUUID {
            XCTFail()
            return
        }

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
        
        // Ensure that the DirectoryFileEntry for the file is marked as deleted.
        guard let entry = try DirectoryFileEntry.fetchSingleRow(db: database, where: DirectoryFileEntry.fileUUIDField.description == fileUUID1) else {
            XCTFail()
            return
        }
        
        XCTAssert(entry.deletedLocally)
        XCTAssert(entry.deletedOnServer)
    }
    
    func testDeletionWithKnownFileGroupWorks() throws {
        try runDeletion(withKnownFileGroupUUID: true)
    }
    
    func testDeletionWithUnknownFileGroupWorks() throws {
        try runDeletion(withKnownFileGroupUUID: false)
    }
    
    func runDeletion(alreadyDeleted: Bool) throws {
        let fileUUID1 = UUID()

        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        let fileGroupUUID = UUID()
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)

        let fileUpload1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .copy(exampleTextFileURL), uuid: fileUUID1)
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload1])
        
        try syncServer.queue(upload: upload)
        waitForUploadsToComplete(numberUploads: 1)
        
        try syncServer.queue(objectDeletion: fileGroupUUID)

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
        
        if alreadyDeleted {
            do {
                try syncServer.queue(objectDeletion: fileGroupUUID)
            } catch {
                return
            }
            
            XCTFail()
        }
    }
    
    func testDeletionAlreadyDeleted() throws {
        try runDeletion(alreadyDeleted: true)
    }
    
    func testDeletionNotAlreadyDeleted() throws {
        try runDeletion(alreadyDeleted: false)
    }
    
    func runDeletionImmediatelyAfter(alreadyDeleted: Bool) throws {
        let fileUUID1 = UUID()

        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        let fileGroupUUID = UUID()
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)

        let fileUpload1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .copy(exampleTextFileURL), uuid: fileUUID1)
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload1])
        
        try syncServer.queue(upload: upload)
        waitForUploadsToComplete(numberUploads: 1)
        
        try syncServer.queue(objectDeletion: fileGroupUUID)
        
        if alreadyDeleted {
            var gotError = false
            do {
                try syncServer.queue(objectDeletion: fileGroupUUID)
            } catch {
                gotError = true
            }
            
            if !gotError {
                XCTFail()
                return
            }
            
            // Fall through to actually do the first queued deletion, otherwise the test will fail-- because of queued network objects.
        }

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
    }

    func testDeletionImmediatelyAfter() throws {
        try runDeletionImmediatelyAfter(alreadyDeleted: true)
    }
    
    func testDeletionNotImmediatelyAfter() throws {
        try runDeletionImmediatelyAfter(alreadyDeleted: false)
    }
    
    func testDeletionWithMultipleFilesInObject() throws {
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        let fileGroupUUID = UUID()
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let fileDeclaration2 = FileDeclaration(fileLabel: "file2", mimeTypes: [.text], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1, fileDeclaration2])
        try syncServer.register(object: example)
        
        let fileUpload1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .copy(exampleTextFileURL), uuid: fileUUID1)
        let fileUpload2 = FileUpload(fileLabel: fileDeclaration2.fileLabel, mimeType: .text, dataSource: .copy(exampleTextFileURL), uuid: fileUUID2)
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload1, fileUpload2])
        
        try syncServer.queue(upload: upload)
        waitForUploadsToComplete(numberUploads: 2)
        
        try syncServer.queue(objectDeletion: fileGroupUUID)

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
        
        // Ensure that the DirectoryFileEntry for the file is marked as deleted.
        guard let fileEntry1 = try DirectoryFileEntry.fetchSingleRow(db: database, where: DirectoryFileEntry.fileUUIDField.description == fileUUID1) else {
            XCTFail()
            return
        }
        
        guard let fileEntry2 = try DirectoryFileEntry.fetchSingleRow(db: database, where: DirectoryFileEntry.fileUUIDField.description == fileUUID2) else {
            XCTFail()
            return
        }
        
        guard let objectEntry = try DirectoryObjectEntry.fetchSingleRow(db: database, where: DirectoryObjectEntry.fileGroupUUIDField.description == fileGroupUUID) else {
            XCTFail()
            return
        }
        
        XCTAssert(objectEntry.deletedLocally)
        XCTAssert(objectEntry.deletedOnServer)
        
        XCTAssert(fileEntry1.deletedLocally)
        XCTAssert(fileEntry1.deletedOnServer)
        
        XCTAssert(fileEntry2.deletedLocally)
        XCTAssert(fileEntry2.deletedOnServer)
    }
    
    func runDeletion(withDeletedSharingGroup: Bool) throws {
        let sharingGroupUUID = try getSharingGroup(db: database)
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.jpeg], changeResolverName: nil)

        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let fileUpload1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .jpeg, dataSource: .copy(exampleTextFileURL), uuid: UUID())
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload1])

        try syncServer.queue(upload: upload)
        waitForUploadsToComplete(numberUploads: 1)
        
        if withDeletedSharingGroup {
            let exp = expectation(description: "exp")
            syncServer.removeFromSharingGroup(sharingGroupUUID: sharingGroupUUID) { error in
                XCTAssertNil(error)
                exp.fulfill()
            }
            waitForExpectations(timeout: 10, handler: nil)
            
            try self.sync()
        }

        if !withDeletedSharingGroup {
            let exp = expectation(description: "exp")
            handlers.deletionCompleted = { _, _ in
                exp.fulfill()
            }
        }
        
        do {
            try syncServer.queue(objectDeletion: upload.fileGroupUUID)
        } catch let error {
            if !withDeletedSharingGroup {
                XCTFail("\(error)")
            }
            return
        }

        if withDeletedSharingGroup {
            XCTFail()
            return
        }
            
        waitForExpectations(timeout: 10, handler: nil)
        
        // Wait for some period of time for the deferred deletion to complete.
        Thread.sleep(forTimeInterval: 5)

        let exp2 = expectation(description: "exp2")
        handlers.syncCompleted = { _, _ in
            exp2.fulfill()
        }
        
        // This `sync` is to trigger the check for the deferred upload completion.
        try syncServer.sync()
        
        let exp3 = expectation(description: "exp2")
        handlers.deferredCompleted = { _, operation, fileGroupUUIDs in
            XCTAssert(operation == .deletion)
            XCTAssert(fileGroupUUIDs.count == 1)
            exp3.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testDeletionWithDeletedSharingGroupFails() throws {
        try runDeletion(withDeletedSharingGroup: true)
    }
    
    func testDeletionWithNonDeletedSharingGroupWorks() throws {
        try runDeletion(withDeletedSharingGroup: false)
    }
    
    // MARK: Prioritization tests
    // See https://github.com/SyncServerII/Neebla/issues/25#issuecomment-898940988

    func testDeletionWhilePendingDeletionFails() throws {
        let sharingGroupUUID = try getSharingGroup(db: database)
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.jpeg], changeResolverName: nil)

        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let fileUpload1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .jpeg, dataSource: .copy(exampleTextFileURL), uuid: UUID())
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload1])

        try syncServer.queue(upload: upload)
        waitForUploadsToComplete(numberUploads: 1)
        
        let exp = expectation(description: "exp")
        handlers.deletionCompleted = { _, _ in
            exp.fulfill()
        }

        // This first deletion should work.
        try syncServer.queue(objectDeletion: upload.fileGroupUUID)

        // A second deletion should fail.
        var failed = false
        do {
            try syncServer.queue(objectDeletion: upload.fileGroupUUID)
        } catch let error {
            failed = true
            guard let error = error as? SyncServerError else {
                XCTFail()
                return
            }
            guard error == .attemptToDeleteAnAlreadyDeletedFile else {
                XCTFail()
                return
            }
        }
        
        guard failed else {
            XCTFail()
            return
        }
            
        waitForExpectations(timeout: 10, handler: nil)
        
        // Wait for some period of time for the deferred deletion to complete.
        Thread.sleep(forTimeInterval: 5)

        let exp2 = expectation(description: "exp2")
        handlers.syncCompleted = { _, _ in
            exp2.fulfill()
        }
        
        // This `sync` is to trigger the check for the deferred upload completion.
        try syncServer.sync()
        
        let exp3 = expectation(description: "exp2")
        handlers.deferredCompleted = { _, operation, fileGroupUUIDs in
            XCTAssert(operation == .deletion)
            XCTAssert(fileGroupUUIDs.count == 1)
            exp3.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testDeletionIsQueuedWhenActiveUpload() throws {
        let sharingGroupUUID = try getSharingGroup(db: database)
        
        let objectType = "Foo"
        let fileGroupUUID = UUID()
        
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.jpeg], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let fileUpload1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .jpeg, dataSource: .copy(exampleTextFileURL), uuid: UUID())
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload1])
        try syncServer.queue(upload: upload)

        try syncServer.queue(objectDeletion: upload.fileGroupUUID)
        
        // There is an active upload. The deletion shouldn't now be active.
        let deletionTracker = try UploadDeletionTracker.fetchSingleRow(db: database, where: UploadDeletionTracker.uuidField.description == upload.fileGroupUUID)
        guard deletionTracker?.status == .notStarted else {
            XCTFail()
            return
        }

        waitForUploadsToComplete(numberUploads: 1)

        // Trigger the deletion and wait for it to complete.
        try syncServer.sync()
        
        let exp = expectation(description: "exp")
        handlers.deletionCompleted = { _, _ in
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        // Wait for some period of time for the deferred deletion to complete.
        Thread.sleep(forTimeInterval: 5)

        let exp2 = expectation(description: "exp2")
        handlers.syncCompleted = { _, _ in
            exp2.fulfill()
        }
        
        // This `sync` is to trigger the check for the deferred upload completion.
        try syncServer.sync()
        
        let exp3 = expectation(description: "exp2")
        handlers.deferredCompleted = { _, operation, fileGroupUUIDs in
            XCTAssert(operation == .deletion)
            XCTAssert(fileGroupUUIDs.count == 1)
            exp3.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testDeletionIsQueuedWhenInactiveUpload() throws {
        let sharingGroupUUID = try getSharingGroup(db: database)
        
        let objectType = "Foo"
        let fileGroupUUID = UUID()
        
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.jpeg], changeResolverName: nil)
        let fileDeclaration2 = FileDeclaration(fileLabel: "file2", mimeTypes: [.jpeg], changeResolverName: nil)
        
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1, fileDeclaration2])
        try syncServer.register(object: example)
        
        let fileUpload1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .jpeg, dataSource: .copy(exampleTextFileURL), uuid: UUID())
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload1])

        try syncServer.queue(upload: upload)
        
        // Setup an inactive upload
        let fileUpload2 = FileUpload(fileLabel: fileDeclaration2.fileLabel, mimeType: .jpeg, dataSource: .copy(exampleTextFileURL), uuid: UUID())
        let upload2 = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload2])
        try syncServer.queue(upload: upload2)
        
        // Wait for first upload to complete.
        waitForUploadsToComplete(numberUploads: 1)

        try syncServer.queue(objectDeletion: upload.fileGroupUUID)
        
        // There is an inactive upload. The deletion shouldn't now be active.
        let deletionTracker = try UploadDeletionTracker.fetchSingleRow(db: database, where: UploadDeletionTracker.uuidField.description == upload.fileGroupUUID)
        guard deletionTracker?.status == .notStarted else {
            XCTFail()
            return
        }
        
        // Trigger the inactive upload and wait for it.
        try syncServer.sync()
        waitForUploadsToComplete(numberUploads: 1)
        
        // Trigger the deletion and wait for it to complete.
        try syncServer.sync()
        
        let exp = expectation(description: "exp")
        handlers.deletionCompleted = { _, _ in
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        // Wait for some period of time for the deferred deletion to complete.
        Thread.sleep(forTimeInterval: 5)

        let exp2 = expectation(description: "exp2")
        handlers.syncCompleted = { _, _ in
            exp2.fulfill()
        }
        
        // This `sync` is to trigger the check for the deferred upload completion.
        try syncServer.sync()
        
        let exp3 = expectation(description: "exp2")
        handlers.deferredCompleted = { _, operation, fileGroupUUIDs in
            XCTAssert(operation == .deletion)
            XCTAssert(fileGroupUUIDs.count == 1)
            exp3.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testDeletionIsQueuedWhenActiveDownload() throws {
        let sharingGroupUUID = try getSharingGroup(db: database)
        
        let objectType = "Foo"
        let fileGroupUUID = UUID()
        
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.jpeg], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let fileUpload1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .jpeg, dataSource: .copy(exampleTextFileURL), uuid: UUID())
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload1])
        try syncServer.queue(upload: upload)
        waitForUploadsToComplete(numberUploads: 1)
        
        let downloadable1 = FileToDownload(uuid: fileUpload1.uuid, fileVersion: 0)
        let downloadables = [downloadable1]
        let downloadObject = ObjectToDownload(fileGroupUUID: fileGroupUUID, downloads: downloadables)
        try syncServer.queue(download: downloadObject)

        try syncServer.queue(objectDeletion: upload.fileGroupUUID)
        
        // There is an active download. The deletion shouldn't now be active.
        let deletionTracker = try UploadDeletionTracker.fetchSingleRow(db: database, where: UploadDeletionTracker.uuidField.description == upload.fileGroupUUID)
        guard deletionTracker?.status == .notStarted else {
            XCTFail()
            return
        }
        
        // Trigger the inactive download and wait for it.
        try syncServer.sync()
        waitForDownloadsToComplete(numberExpected: 1)
        
        // Trigger the deletion and wait for it to complete.
        try syncServer.sync()
        
        let exp = expectation(description: "exp")
        handlers.deletionCompleted = { _, _ in
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        // Wait for some period of time for the deferred deletion to complete.
        Thread.sleep(forTimeInterval: 5)

        let exp2 = expectation(description: "exp2")
        handlers.syncCompleted = { _, _ in
            exp2.fulfill()
        }
        
        // This `sync` is to trigger the check for the deferred upload completion.
        try syncServer.sync()
        
        let exp3 = expectation(description: "exp2")
        handlers.deferredCompleted = { _, operation, fileGroupUUIDs in
            XCTAssert(operation == .deletion)
            XCTAssert(fileGroupUUIDs.count == 1)
            exp3.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testDeletionIsQueuedWhenInactiveDownload() throws {
        let sharingGroupUUID = try getSharingGroup(db: database)
        
        let objectType = "Foo"
        let fileGroupUUID = UUID()
        
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.jpeg], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let fileUpload1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .jpeg, dataSource: .copy(exampleTextFileURL), uuid: UUID())
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload1])
        try syncServer.queue(upload: upload)
        waitForUploadsToComplete(numberUploads: 1)
        
        let downloadable1 = FileToDownload(uuid: fileUpload1.uuid, fileVersion: 0)
        let downloadables = [downloadable1]
        let downloadObject = ObjectToDownload(fileGroupUUID: fileGroupUUID, downloads: downloadables)
        try syncServer.queue(download: downloadObject)

        // This second one will be queued.
        try syncServer.queue(download: downloadObject)
        
        // Wait for the first download to complete.
        waitForDownloadsToComplete(numberExpected: 1)

        try syncServer.queue(objectDeletion: upload.fileGroupUUID)
        
        // There is an inactive download. The deletion shouldn't now be active.
        let deletionTracker = try UploadDeletionTracker.fetchSingleRow(db: database, where: UploadDeletionTracker.uuidField.description == upload.fileGroupUUID)
        guard deletionTracker?.status == .notStarted else {
            XCTFail()
            return
        }
        
        // Trigger the inactive download and wait for it.
        try syncServer.sync()
        waitForDownloadsToComplete(numberExpected: 1)
        
        // Trigger the deletion and wait for it to complete.
        try syncServer.sync()
        
        let exp = expectation(description: "exp")
        handlers.deletionCompleted = { _, _ in
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        // Wait for some period of time for the deferred deletion to complete.
        Thread.sleep(forTimeInterval: 5)

        let exp2 = expectation(description: "exp2")
        handlers.syncCompleted = { _, _ in
            exp2.fulfill()
        }
        
        // This `sync` is to trigger the check for the deferred upload completion.
        try syncServer.sync()
        
        let exp3 = expectation(description: "exp2")
        handlers.deferredCompleted = { _, operation, fileGroupUUIDs in
            XCTAssert(operation == .deletion)
            XCTAssert(fileGroupUUIDs.count == 1)
            exp3.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
    }
}
