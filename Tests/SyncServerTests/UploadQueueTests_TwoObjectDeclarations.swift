import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn
import ChangeResolvers
@testable import TestsCommon

class UploadQueueTests_TwoObjectDeclarations: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, Delegate, SyncServerTests {
    
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
        config = Configuration(appGroupIdentifier: nil, serverURL: serverURL, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true)
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
        
        let count = try NetworkCache.numberRows(db: database)
        XCTAssert(count == 0, "\(count)")
    }
    
    func testQueueObject1FollowedByQueueObject2UploadsBoth() throws {
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()

        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        // First object
        let objectType1 = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let example1 = ExampleDeclaration(objectType: objectType1, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example1)
        
        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .copy(exampleTextFileURL), uuid: fileUUID1)
        let upload = ObjectUpload(objectType: objectType1, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: [file1])
        try syncServer.queue(upload: upload)
        
        // Second object
        let objectType2 = "Foobly"
        let fileDeclaration2 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let example2 = ExampleDeclaration(objectType: objectType2, declaredFiles: [fileDeclaration2])
        try syncServer.register(object: example2)
        
        let file2 = FileUpload(fileLabel: fileDeclaration2.fileLabel, mimeType: .text, dataSource: .copy(exampleTextFileURL), uuid: fileUUID2)
        let upload2 = ObjectUpload(objectType: objectType2, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: [file2])
        try syncServer.queue(upload: upload2)
        
        waitForUploadsToComplete(numberUploads: 2)
        
        XCTAssert(try UploadFileTracker.numberRows(db: database) == 0)
        XCTAssert(try UploadObjectTracker.numberRows(db: database) == 0)
        XCTAssert(try DirectoryFileEntry.numberRows(db: database) == 2)
        XCTAssert(try DirectoryObjectEntry.numberRows(db: database) == 2)
    }

    /* The purpose here is do the following:
        queue object1
        queue object1
        queue object2
        queue object2
        Wait
        Should be in a state where both object1 and object2 are waiting for upload.
        Calling sync should upload both of those.
    */
    func testTwoUploadsOfTwoDifferentObjectsTwice() throws {
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()

        let fileGroupUUID1 = UUID()
        let fileGroupUUID2 = UUID()

        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        // Object1
        let objectType1 = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: CommentFile.changeResolverName)
        let example1 = ExampleDeclaration(objectType: objectType1, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example1)

        func object1(v0: Bool) throws {
            let upload:ObjectUpload
            
            if v0 {
                let commentFile = CommentFile()
                let commentFileData = try commentFile.getData()
                let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .data(commentFileData), uuid: fileUUID1)
                upload = ObjectUpload(objectType: objectType1, fileGroupUUID: fileGroupUUID1, sharingGroupUUID: sharingGroupUUID, uploads: [file1])
            }
            else {
                let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
                let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .data(comment.updateContents), uuid: fileUUID1)
                upload = ObjectUpload(objectType: objectType1, fileGroupUUID: fileGroupUUID1, sharingGroupUUID: sharingGroupUUID, uploads: [file1])
            }

            try syncServer.queue(upload: upload)
        }
        
        // Object2
        let objectType2 = "Foo"
        let fileDeclaration2 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: CommentFile.changeResolverName)
        let example2 = ExampleDeclaration(objectType: objectType1, declaredFiles: [fileDeclaration2])
        try syncServer.register(object: example2)
                
        func object2(v0: Bool) throws {
            let upload:ObjectUpload
            
            if v0 {
                let commentFile = CommentFile()
                let commentFileData = try commentFile.getData()
                let file1 = FileUpload(fileLabel: fileDeclaration2.fileLabel, mimeType: .text, dataSource: .data(commentFileData), uuid: fileUUID2)
                upload = ObjectUpload(objectType: objectType2, fileGroupUUID: fileGroupUUID2, sharingGroupUUID: sharingGroupUUID, uploads: [file1])
            }
            else {
                let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
                let file1 = FileUpload(fileLabel: fileDeclaration2.fileLabel, mimeType: .text, dataSource: .data(comment.updateContents), uuid: fileUUID2)
                upload = ObjectUpload(objectType: objectType2, fileGroupUUID: fileGroupUUID2, sharingGroupUUID: sharingGroupUUID, uploads: [file1])
            }

            try syncServer.queue(upload: upload)
        }
        
        var count = 0
        handlers.extras.uploadQueued = { _ in
            count += 1
        }
        
        try object1(v0: true)
        try object1(v0: false)
        try object2(v0: true)
        try object2(v0: false)

        // Wait for first upload instances (v0's).
        waitForUploadsToComplete(numberUploads: 2)
        XCTAssert(count == 2)

        // Trigger the second upload instances (vN's).
        try syncServer.sync()
        waitForUploadsToComplete(numberUploads: 2, v0Upload: false)

        // Wait for some period of time for the deferred uploads to complete.
        // There are two file groups, therefore two deferred uploads are getting processed. We may need to wait for the periodic uploader to run on the server, so giving a long interval here.
        // See also https://github.com/SyncServerII/ServerMain/issues/6
        Thread.sleep(forTimeInterval: 40)

        // This `sync` is to trigger the check for the deferred upload completion.
        try syncServer.sync()

        let exp = expectation(description: "exp")
        handlers.deferredCompleted = { _, operation, fileGroupUUIDs in
            XCTAssert(operation == .upload)
            XCTAssert(fileGroupUUIDs.count == 2)
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        XCTAssert(try UploadFileTracker.numberRows(db: database) == 0)
        XCTAssert(try UploadObjectTracker.numberRows(db: database) == 0)
        XCTAssert(try DirectoryFileEntry.numberRows(db: database) == 2)
        XCTAssert(try DirectoryObjectEntry.numberRows(db: database) == 2)

        // These are only version 0 because only updates beyond v0 on download.
        
        guard let fileVersion1 = try DirectoryFileEntry.fileVersion(fileUUID: fileUUID1, db: database) else {
            XCTFail()
            return
        }
        XCTAssert(fileVersion1 == 0)
        
        guard let fileVersion2 = try DirectoryFileEntry.fileVersion(fileUUID: fileUUID2, db: database) else {
            XCTFail()
            return
        }
        XCTAssert(fileVersion2 == 0)
    }
    
    func runUpload(usingFileFromOtherDeclarationFails: Bool) throws {
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()

        let fileGroupUUID1 = UUID()
        let fileGroupUUID2 = UUID()

        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        // Object1
        let objectType1 = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: CommentFile.changeResolverName)
        let example1 = ExampleDeclaration(objectType: objectType1, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example1)

        func object1v0() throws {
            let commentFile = CommentFile()
            let commentFileData = try commentFile.getData()
            let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .data(commentFileData), uuid: fileUUID1)
            let upload = ObjectUpload(objectType: objectType1, fileGroupUUID: fileGroupUUID1, sharingGroupUUID: sharingGroupUUID, uploads: [file1])
            try syncServer.queue(upload: upload)
        }
        
        // Object2
        let objectType2 = "Foo"
        let fileDeclaration2 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: CommentFile.changeResolverName)
        let example2 = ExampleDeclaration(objectType: objectType2, declaredFiles: [fileDeclaration2])
        try syncServer.register(object: example2)

        func object2v0() throws {
            let commentFile = CommentFile()
            let commentFileData = try commentFile.getData()
            let file1 = FileUpload(fileLabel: fileDeclaration2.fileLabel, mimeType: .text, dataSource: .data(commentFileData), uuid: fileUUID2)
            let upload = ObjectUpload(objectType: objectType2, fileGroupUUID: fileGroupUUID2, sharingGroupUUID: sharingGroupUUID, uploads: [file1])
            try syncServer.queue(upload: upload)
        }
        
        try object1v0()
        try object2v0()
                
        // Wait for first upload instances (v0's).
        waitForUploadsToComplete(numberUploads: 2)
        
        let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        
        let uploadFileUUID:UUID
        let fileLabel:String
        if usingFileFromOtherDeclarationFails {
            // Using file from object1-- `queue` should fail
            uploadFileUUID = fileUUID1
            fileLabel = fileDeclaration1.fileLabel
        }
        else {
            uploadFileUUID = fileUUID2
            fileLabel = fileDeclaration2.fileLabel
        }
        
        let file1 = FileUpload(fileLabel: fileLabel, mimeType: .text, dataSource: .data(comment.updateContents), uuid: uploadFileUUID)
        let upload = ObjectUpload(objectType: objectType2, fileGroupUUID: fileGroupUUID2, sharingGroupUUID: sharingGroupUUID, uploads: [file1])
        
        do {
            try syncServer.queue(upload: upload)
        } catch let error {
            logger.debug("\(error)")
            if !usingFileFromOtherDeclarationFails {
                XCTFail()
            }
            return
        }
        
        if usingFileFromOtherDeclarationFails {
            XCTFail()
            return
        }
        
        // Trigger the second upload instances, vN.
        try syncServer.sync()
        waitForUploadsToComplete(numberUploads: 1, v0Upload: false)

        // Wait for some period of time for the deferred upload to complete.
        Thread.sleep(forTimeInterval: 5)

        // This `sync` is to trigger the check for the deferred upload completion.
        try syncServer.sync()

        let exp = expectation(description: "exp")
        handlers.deferredCompleted = { _, operation, fileGroupUUIDs in
            XCTAssert(operation == .upload)
            XCTAssert(fileGroupUUIDs.count == 1)
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        XCTAssert(try UploadFileTracker.numberRows(db: database) == 0)
        XCTAssert(try UploadObjectTracker.numberRows(db: database) == 0)
        XCTAssert(try DirectoryFileEntry.numberRows(db: database) == 2)
        XCTAssert(try DirectoryObjectEntry.numberRows(db: database) == 2)
    }
    
    func testRunUploadUsingFileFromOtherDeclarationFails() throws {
        try runUpload(usingFileFromOtherDeclarationFails: true)
    }
    
    func testRunUploadUsingFileFromSameDeclarationWorks() throws {
        try runUpload(usingFileFromOtherDeclarationFails: false)
    }
}
