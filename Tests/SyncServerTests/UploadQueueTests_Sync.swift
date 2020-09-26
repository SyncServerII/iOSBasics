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

class UploadQueueTests_Sync: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, Delegate, SyncServerTests {
    var deviceUUID: UUID!
    var hashingManager: HashingManager!
    var api: ServerAPI!
    var syncServer: SyncServer!
    var handlers = DelegateHandlers()
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
        let fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
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
    
    // Since this uploads a vN file, it *must* use a change resolver.
    func testQueueObjectAlreadyRegisteredWorks() throws {
        let fileUUID1 = UUID()
        let fileGroupUUID1 = UUID()
        
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let declaration = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, appMetaData: nil, changeResolverName: CommentFile.changeResolverName)
        let declarations = Set<FileDeclaration>([declaration])

        let testObject = ObjectDeclaration(fileGroupUUID: fileGroupUUID1, objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
            
        func object1(v0: Bool) throws {
            let uploadables:Set<FileUpload>
            
            if v0 {
                let commentFile = CommentFile()
                let commentFileData = try commentFile.getData()
                let uploadable = FileUpload(uuid: fileUUID1, dataSource: .data(commentFileData))
                uploadables = Set<FileUpload>([uploadable])
            }
            else {
                let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
                let uploadable = FileUpload(uuid: fileUUID1, dataSource: .data(comment.updateContents))
                uploadables = Set<FileUpload>([uploadable])
            }

            try syncServer.queue(uploads: uploadables, declaration: testObject)
        }
        
        var count = 0
        handlers.extras.uploadQueued = { _ in
            count += 1
        }
        
        try object1(v0: true)
        
        // This second one should work also-- but not trigger an upload-- because its for the same file group as the immediately prior `queue`. i.e., the active upload.
        try object1(v0: false)
        
        let objectCount = try DeclaredObjectModel.numberRows(db: database,
            where: testObject.declObjectId == DeclaredObjectModel.fileGroupUUIDField.description)
        XCTAssert(objectCount == 1)
        
        let fileCount = try DeclaredFileModel.numberRows(db: database, where: testObject.declObjectId == DeclaredFileModel.fileGroupUUIDField.description)
        XCTAssert(fileCount == 1)

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
        XCTAssert(try DirectoryEntry.numberRows(db: database) == 1)
    }
    
    func testUploadFileAfterInitialQueueOtherDeclaredFile() throws {
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()
        
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, appMetaData: nil, changeResolverName: nil)
        let declaration2 = FileDeclaration(uuid: fileUUID2, mimeType: MimeType.text, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration1, declaration2])
        
        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleTextFileURL))
        let uploadables1 = Set<FileUpload>([uploadable1])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)

        try syncServer.queue(uploads: uploadables1, declaration: testObject)

        let uploadable2 = FileUpload(uuid: fileUUID2, dataSource: .copy(exampleTextFileURL))
        let uploadables2 = Set<FileUpload>([uploadable2])
        
        do {
            try syncServer.queue(uploads: uploadables2, declaration: testObject)
        } catch {
            XCTFail()
            return
        }
        
        // Wait for 1st upload to complete.
        waitForUploadsToComplete(numberUploads: 1)
        
        // Need to trigger second upload
        try syncServer.sync()
        
        // Wait for 2nd upload to complete.
        waitForUploadsToComplete(numberUploads: 1)
    }
    
    func runQueueObject(fileHasBeenDeleted: Bool) throws {
        let fileUUID1 = UUID()
        let fileGroupUUID1 = UUID()
        
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let declaration = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, appMetaData: nil, changeResolverName: CommentFile.changeResolverName)
        let declarations = Set<FileDeclaration>([declaration])

        let testObject = ObjectDeclaration(fileGroupUUID: fileGroupUUID1, objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
            
        func object1(v0: Bool) throws {
            let uploadables:Set<FileUpload>
            
            if v0 {
                let commentFile = CommentFile()
                let commentFileData = try commentFile.getData()
                let uploadable = FileUpload(uuid: fileUUID1, dataSource: .data(commentFileData))
                uploadables = Set<FileUpload>([uploadable])
            }
            else {
                let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
                let uploadable = FileUpload(uuid: fileUUID1, dataSource: .data(comment.updateContents))
                uploadables = Set<FileUpload>([uploadable])
            }

            try syncServer.queue(uploads: uploadables, declaration: testObject)
        }
        
        var count = 0
        handlers.extras.uploadQueued = { _ in
            count += 1
        }
        
        try object1(v0: true)
        
        if fileHasBeenDeleted {
            guard let entry = try DirectoryEntry.fetchSingleRow(db: database, where: fileUUID1 == DirectoryEntry.fileUUIDField.description) else {
                throw DatabaseModelError.noObject
            }
            
            try entry.update(setters:
                DirectoryEntry.deletedLocallyField.description <- true
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
        
        let objectCount = try DeclaredObjectModel.numberRows(db: database,
            where: testObject.declObjectId == DeclaredObjectModel.fileGroupUUIDField.description)
        XCTAssert(objectCount == 1)
        
        let fileCount = try DeclaredFileModel.numberRows(db: database, where: testObject.declObjectId == DeclaredFileModel.fileGroupUUIDField.description)
        XCTAssert(fileCount == 1)

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
        XCTAssert(try DirectoryEntry.numberRows(db: database) == 1)
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
        
        let declaration = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, appMetaData: nil, changeResolverName: CommentFile.changeResolverName)
        let declarations = Set<FileDeclaration>([declaration])

        let testObject = ObjectDeclaration(fileGroupUUID: fileGroupUUID1, objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
            
        func object1(v0: Bool, v1Id: UUID = Foundation.UUID()) throws {
            let uploadables:Set<FileUpload>
            
            if v0 {
                let commentFile = CommentFile()
                let commentFileData = try commentFile.getData()
                let uploadable = FileUpload(uuid: fileUUID1, dataSource: .data(commentFileData))
                uploadables = Set<FileUpload>([uploadable])
            }
            else {
                let comment = ExampleComment(messageString: "Example", id: v1Id.uuidString)
                let uploadable = FileUpload(uuid: fileUUID1, dataSource: .data(comment.updateContents))
                uploadables = Set<FileUpload>([uploadable])
            }

            try syncServer.queue(uploads: uploadables, declaration: testObject)
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
            where: testObject.declObjectId == DeclaredObjectModel.fileGroupUUIDField.description)
        XCTAssert(objectCount == 1)
        
        let fileCount = try DeclaredFileModel.numberRows(db: database, where: testObject.declObjectId == DeclaredFileModel.fileGroupUUIDField.description)
        XCTAssert(fileCount == 1)

        waitForUploadsToComplete(numberUploads: 1)
        XCTAssert(count == 2)

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
        
        // Trigger the third upload instance.
        try syncServer.sync()
        waitForUploadsToComplete(numberUploads: 1, v0Upload: false)

        // Wait for some period of time for the deferred upload to complete.
        Thread.sleep(forTimeInterval: 5)

        // This `sync` is to trigger the check for the deferred upload completion.
        try syncServer.sync()

        let exp3 = expectation(description: "exp2")
        handlers.deferredCompleted = { _, operation, count in
            exp3.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)

        XCTAssert(try UploadFileTracker.numberRows(db: database) == 0)
        XCTAssert(try UploadObjectTracker.numberRows(db: database) == 0)
        XCTAssert(try DirectoryEntry.numberRows(db: database) == 1)
    }
    
    func testVNAndV0UploadFails() throws {
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()
        let fileGroupUUID1 = UUID()
        
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        let commentFile = CommentFile()
        
        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, appMetaData: nil, changeResolverName: CommentFile.changeResolverName)
        let declaration2 = FileDeclaration(uuid: fileUUID2, mimeType: MimeType.text, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration1, declaration2])

        let testObject = ObjectDeclaration(fileGroupUUID: fileGroupUUID1, objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        // v0 upload for fileUUID1
        let commentFileData = try commentFile.getData()
        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .data(commentFileData))
        let uploadables1 = Set<FileUpload>([uploadable1])
        try syncServer.queue(uploads: uploadables1, declaration: testObject)

        waitForUploadsToComplete(numberUploads: 1)
                
        // vN + v0 upload attempt
        let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        
        // v1
        let uploadable2 = FileUpload(uuid: fileUUID1, dataSource: .data(comment.updateContents))
        
        // v0
        let uploadable3 = FileUpload(uuid: fileUUID2, dataSource: .copy(exampleTextFileURL))
        let uploadables2 = Set<FileUpload>([uploadable2, uploadable3])
        
        // Fails because we're not allowing uploads of v0 and vN together within the same `queue` for the same file group.
        do {
            try syncServer.queue(uploads: uploadables2, declaration: testObject)
        } catch {
            // Need to remove both of the url's for the failed uploads or the test will fail in the cleanup.
            guard let fileTracker1 = try UploadFileTracker.fetchSingleRow(db: database, where: fileUUID1 == UploadFileTracker.fileUUIDField.description),
                let localURL1 = fileTracker1.localURL else {
                XCTFail()
                return
            }
            
            guard let fileTracker2 = try UploadFileTracker.fetchSingleRow(db: database, where: fileUUID2 == UploadFileTracker.fileUUIDField.description),
                let localURL2 = fileTracker2.localURL else {
                XCTFail()
                return
            }
            
            try FileManager.default.removeItem(at: localURL1)
            try FileManager.default.removeItem(at: localURL2)
            return
        }
        
        XCTFail()
    }
}
