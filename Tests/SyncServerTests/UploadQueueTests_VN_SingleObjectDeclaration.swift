import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn
@testable import TestsCommon
import ChangeResolvers

class UploadQueueTests_VN_SingleObjectDeclaration: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, Delegate, SyncServerTests {
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
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, reachability: FakeReachability(), configuration: config, signIns: fakeSignIns)
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

    func testQueueObjectAlreadyRegisteredWorks() throws {
        let fileUUID = UUID()
        // try self.sync()
        // let sharingGroupUUID = try getSharingGroupUUID()
        let sharingGroupUUID = try getSharingGroup(db: database)
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: CommentFile.changeResolverName)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let commentFile = CommentFile()
        let commentFileData = try commentFile.getData()
                
        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .data(commentFileData), uuid: fileUUID)
        let uploads = [file1]
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: uploads)
        
        var queuedCount = 0
        handlers.extras.uploadQueued = { _ in
            queuedCount += 1
        }

        try syncServer.queue(upload: upload)
        XCTAssert(queuedCount == 0)

        // This second one should work also-- but not trigger an upload-- because its for the same file group as the immediately prior `queue`. i.e., the active upload.
        try syncServer.queue(upload: upload)
        // Can't do this yet because of async delegate calls.
        // XCTAssert(queuedCount == 1, "\(queuedCount)")

        let count = try DirectoryObjectEntry.numberRows(db: database,
            where: upload.fileGroupUUID == DirectoryObjectEntry.fileGroupUUIDField.description)
        XCTAssert(count == 1)

        let count2 = try DirectoryFileEntry.numberRows(db: database, where: upload.fileGroupUUID == DirectoryFileEntry.fileGroupUUIDField.description)
        XCTAssert(count2 == 1)
        
        waitForUploadsToComplete(numberUploads: 1)
        XCTAssert(queuedCount == 1, "\(queuedCount)")

        let fileTrackerCount = try UploadFileTracker.numberRows(db: database)
        XCTAssert(fileTrackerCount == 1)
        
        // Until I get the second tier queued uploads working, need to remove the remaining non-uploaded file to not get a test failure.
        guard let tracker = try UploadFileTracker.fetchSingleRow(db: database, where: fileUUID == UploadFileTracker.fileUUIDField.description) else {
            XCTFail()
            return
        }
        
        guard let url = tracker.localURL else {
            XCTFail()
            return
        }
        
        try FileManager.default.removeItem(at: url)
    }
    
    func runUpload(badUUIDButSameFileLabel: Bool) throws {
        let fileUUID = UUID()
        // try self.sync()
        // let sharingGroupUUID = try getSharingGroupUUID()
        let sharingGroupUUID = try getSharingGroup(db: database)
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: CommentFile.changeResolverName)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let commentFile = CommentFile()
        let commentFileData = try commentFile.getData()
                
        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .data(commentFileData), uuid: fileUUID)
        let uploads = [file1]
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: uploads)

        try syncServer.queue(upload: upload)
        waitForUploadsToComplete(numberUploads: 1)
        
        let fileUUID2:UUID
        if badUUIDButSameFileLabel {
            fileUUID2 = UUID()
        }
        else {
            fileUUID2 = fileUUID
        }

        let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        
        let file2 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .data(comment.updateContents), uuid: fileUUID2)
        let uploads2 = [file2]
        
        let upload2 = ObjectUpload(objectType: objectType, fileGroupUUID: upload.fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: uploads2)
        
        do {
            try syncServer.queue(upload: upload2)
        } catch let error {
            if !badUUIDButSameFileLabel {
                XCTFail("\(error)")
            }
            return
        }
        
        if badUUIDButSameFileLabel {
            XCTFail()
            return
        }
        
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
    }
    
    func testBadUUIDButSameFileLabelFails() throws {
        try runUpload(badUUIDButSameFileLabel: true)
    }
    
    func testGoodUUIDAndSameFileLabelWorks() throws {
        try runUpload(badUUIDButSameFileLabel: false)
    }

    func runUpload(goodUUIDButBadFileLabel: Bool) throws {
        let fileUUID = UUID()
        // try self.sync()
        // let sharingGroupUUID = try getSharingGroupUUID()
        let sharingGroupUUID = try getSharingGroup(db: database)
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: CommentFile.changeResolverName)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let commentFile = CommentFile()
        let commentFileData = try commentFile.getData()
                
        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .data(commentFileData), uuid: fileUUID)
        let uploads = [file1]
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: uploads)

        try syncServer.queue(upload: upload)
        waitForUploadsToComplete(numberUploads: 1)
        
        let fileLabel2:String
        if goodUUIDButBadFileLabel {
            fileLabel2 = fileDeclaration1.fileLabel + "Foobly"
        }
        else {
            fileLabel2 = fileDeclaration1.fileLabel
        }

        let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        
        let file2 = FileUpload(fileLabel: fileLabel2, mimeType: .text, dataSource: .data(comment.updateContents), uuid: fileUUID)
        let uploads2 = [file2]
        
        let upload2 = ObjectUpload(objectType: objectType, fileGroupUUID: upload.fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: uploads2)
        
        do {
            try syncServer.queue(upload: upload2)
        } catch let error {
            if !goodUUIDButBadFileLabel {
                XCTFail("\(error)")
            }
            return
        }
        
        if goodUUIDButBadFileLabel {
            XCTFail()
            return
        }
        
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
    }

    func testGoodUUIDButBadFileLabelFails() throws {
        try runUpload(goodUUIDButBadFileLabel: true)
    }
    
    func testGoodUUIDAndGoodFileLabelWorks() throws {
        try runUpload(goodUUIDButBadFileLabel: false)
    }
    
    func runUpload(vNUploadWithChangeResolver: Bool) throws {
        let fileUUID = UUID()
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        var changeResolver: String?
        if vNUploadWithChangeResolver {
            changeResolver = CommentFile.changeResolverName
        }
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: changeResolver)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let commentFile = CommentFile()
        let commentFileData = try commentFile.getData()
                
        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .data(commentFileData), uuid: fileUUID)
        let uploads = [file1]
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: uploads)

        try syncServer.queue(upload: upload)
        waitForUploadsToComplete(numberUploads: 1)

        let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        
        let file2 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .data(comment.updateContents), uuid: fileUUID)
        let uploads2 = [file2]
        
        let upload2 = ObjectUpload(objectType: objectType, fileGroupUUID: upload.fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: uploads2)
        
        do {
            try syncServer.queue(upload: upload2)
        } catch let error {
            if vNUploadWithChangeResolver {
                XCTFail("\(error)")
            }
            return
        }
        
        if !vNUploadWithChangeResolver {
            XCTFail()
            return
        }
        
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
    }
    
    func testvNUploadWithoutChangeResolverFails() throws {
        try runUpload(vNUploadWithChangeResolver: false)
    }
    
    func testvNUploadWithChangeResolverWorks() throws {
        try runUpload(vNUploadWithChangeResolver: true)
    }
    
    func testVNUploadWithWrongMimeTypeFails() throws {
        let fileUUID = UUID()
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let changeResolver = CommentFile.changeResolverName

        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: changeResolver)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let commentFile = CommentFile()
        let commentFileData = try commentFile.getData()
                
        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .data(commentFileData), uuid: fileUUID)
        let uploads = [file1]
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: uploads)

        try syncServer.queue(upload: upload)
        waitForUploadsToComplete(numberUploads: 1)

        let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        
        let file2 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .png, dataSource: .data(comment.updateContents), uuid: fileUUID)
        let uploads2 = [file2]
        
        let upload2 = ObjectUpload(objectType: objectType, fileGroupUUID: upload.fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: uploads2)

        do {
            try syncServer.queue(upload: upload2)
        } catch let error {
            guard let syncServerError = error as? SyncServerError else {
                XCTFail()
                return
            }
            XCTAssert(syncServerError == .attemptToUploadWithDifferentMimeType)
            return
        }
        XCTFail()
    }
    
    func testVNUploadNilMimeTypeWhenMoreThanOneMimeTypeFails() throws {
        let fileUUID = UUID()
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let changeResolver = CommentFile.changeResolverName

        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text, .png], changeResolverName: changeResolver)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let commentFile = CommentFile()
        let commentFileData = try commentFile.getData()
                
        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .data(commentFileData), uuid: fileUUID)
        let uploads = [file1]
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: uploads)

        try syncServer.queue(upload: upload)
        waitForUploadsToComplete(numberUploads: 1)

        let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        
        let file2 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .data(comment.updateContents), uuid: fileUUID)
        let uploads2 = [file2]
        
        let upload2 = ObjectUpload(objectType: objectType, fileGroupUUID: upload.fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: uploads2)

        do {
            try syncServer.queue(upload: upload2)
        } catch let error {
            guard let syncServerError = error as? SyncServerError else {
                XCTFail()
                return
            }
            XCTAssert(syncServerError == .nilUploadMimeTypeButNotJustOneMimeTypeInDeclaration)
            return
        }
        XCTFail()
    }
    
    // This is a test for an issue that arose on 3/14/21. Got a server error:
    //  [FileController+UploadFile.swift:52 finish(_:params:)] v0 contents for change resolver (CommentFile) were not valid:
    // when I uploaded an image and quickly added a comment.
    func testV0ContentsNotValid() throws {
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

        try syncServer.queue(upload: upload)
        //waitForUploadsToComplete(numberUploads: 2, v0Upload: true)

        let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        
        let file3 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .data(comment.updateContents), uuid: fileUUID1)
        let uploads2 = [file3]
        
        let upload2 = ObjectUpload(objectType: objectType, fileGroupUUID: upload.fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: uploads2)
        
        try syncServer.queue(upload: upload2)
        
/*
[2021-03-16T01:28:22.994Z] [INFO] [FileController+UploadFile.swift:180 uploadFile(params:)] Uploading first version of file.
[2021-03-16T01:28:22.997Z] [ERROR] [FileController+UploadFile.swift:52 finish(_:params:)] No fileLabel given for a v0 file.
[2021-03-16T01:28:23.000Z] [ERROR] [RequestHandler.swift:74 failWithError(failureResult:)] No fileLabel given for a v0 file.
[2021-03-16T01:28:23.000Z] [INFO] [RequestHandler.swift:145 endWith(clientResponse:)] REQUEST /Index: ABOUT TO END ...
[2021-03-16T01:28:23.002Z] [INFO] [RequestHandler.swift:145 endWith(clientResponse:)] REQUEST /UploadFile: ABOUT TO END ...
[2021-03-16T01:28:23.004Z] [INFO] [RequestHandler.swift:149 endWith(clientResponse:)] REQUEST /Index: STATUS CODE: OK
[2021-03-16T01:28:23.006Z] [INFO] [RequestHandler.swift:149 endWith(clientResponse:)] REQUEST /UploadFile: STATUS CODE: internalServerError
         */
        
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
}
