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

    func testQueueObjectAlreadyRegisteredWorks() throws {
        let fileUUID = UUID()
        // try self.sync()
        // let sharingGroupUUID = try getSharingGroupUUID()
        let sharingGroupUUID = try getSharingGroup(db: database)
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeType: .text, changeResolverName: CommentFile.changeResolverName)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let commentFile = CommentFile()
        let commentFileData = try commentFile.getData()
                
        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .data(commentFileData), uuid: fileUUID)
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
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeType: .text, changeResolverName: CommentFile.changeResolverName)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let commentFile = CommentFile()
        let commentFileData = try commentFile.getData()
                
        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .data(commentFileData), uuid: fileUUID)
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
        
        let file2 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .data(comment.updateContents), uuid: fileUUID2)
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
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeType: .text, changeResolverName: CommentFile.changeResolverName)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let commentFile = CommentFile()
        let commentFileData = try commentFile.getData()
                
        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .data(commentFileData), uuid: fileUUID)
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
        
        let file2 = FileUpload(fileLabel: fileLabel2, dataSource: .data(comment.updateContents), uuid: fileUUID)
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
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeType: .text, changeResolverName: changeResolver)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let commentFile = CommentFile()
        let commentFileData = try commentFile.getData()
                
        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .data(commentFileData), uuid: fileUUID)
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
}