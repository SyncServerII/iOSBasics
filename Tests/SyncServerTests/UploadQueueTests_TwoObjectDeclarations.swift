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
        
        let count = try NetworkCache.numberRows(db: database)
        XCTAssert(count == 0, "\(count)")
    }
    
    func testQueueObject1FollowedByQueueObject2UploadsBoth() throws {
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()

        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        // First object
        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, appMetaData: nil, changeResolverName: nil)
        let declarations1 = Set<FileDeclaration>([declaration1])
        
        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleTextFileURL))
        let uploadables1 = Set<FileUpload>([uploadable1])

        let testObject1 = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations1)
        
        try syncServer.queue(uploads: uploadables1, declaration: testObject1)
        
        // Second object
        let declaration2 = FileDeclaration(uuid: fileUUID2, mimeType: MimeType.text, appMetaData: nil, changeResolverName: nil)
        let declarations2 = Set<FileDeclaration>([declaration2])
        
        let uploadable2 = FileUpload(uuid: fileUUID2, dataSource: .copy(exampleTextFileURL))
        let uploadables2 = Set<FileUpload>([uploadable2])

        let testObject2 = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations2)
        
        try syncServer.queue(uploads: uploadables2, declaration: testObject2)

        waitForUploadsToComplete(numberUploads: 2)
        
        XCTAssert(try UploadFileTracker.numberRows(db: database) == 0)
        XCTAssert(try UploadObjectTracker.numberRows(db: database) == 0)
        XCTAssert(try DirectoryEntry.numberRows(db: database) == 2)
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
        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, appMetaData: nil, changeResolverName: CommentFile.changeResolverName)
        let declarations1 = Set<FileDeclaration>([declaration1])

        let testObject1 = ObjectDeclaration(fileGroupUUID: fileGroupUUID1, objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations1)

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

            try syncServer.queue(uploads: uploadables, declaration: testObject1)
        }
        
        // Object2
        let declaration2 = FileDeclaration(uuid: fileUUID2, mimeType: MimeType.text, appMetaData: nil, changeResolverName: CommentFile.changeResolverName)
        let declarations2 = Set<FileDeclaration>([declaration2])

        let testObject2 = ObjectDeclaration(fileGroupUUID: fileGroupUUID2, objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations2)
        
        func object2(v0: Bool) throws {
            let uploadables:Set<FileUpload>
            
            if v0 {
                let commentFile = CommentFile()
                let commentFileData = try commentFile.getData()
                let uploadable = FileUpload(uuid: fileUUID2, dataSource: .data(commentFileData))
                uploadables = Set<FileUpload>([uploadable])
            }
            else {
                let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
                let uploadable = FileUpload(uuid: fileUUID2, dataSource: .data(comment.updateContents))
                uploadables = Set<FileUpload>([uploadable])
            }

            try syncServer.queue(uploads: uploadables, declaration: testObject2)
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
        handlers.deferredCompleted = { _, operation, numberCompleted in
            XCTAssert(operation == .upload)
            XCTAssert(numberCompleted == 2)
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        XCTAssert(try UploadFileTracker.numberRows(db: database) == 0)
        XCTAssert(try UploadObjectTracker.numberRows(db: database) == 0)
        XCTAssert(try DirectoryEntry.numberRows(db: database) == 2)
        
        // These are only version 0 because only updates beyond v0 on download.
        
        guard let fileVersion1 = try DirectoryEntry.fileVersion(fileUUID: fileUUID1, db: database) else {
            XCTFail()
            return
        }
        XCTAssert(fileVersion1 == 0)
        
        guard let fileVersion2 = try DirectoryEntry.fileVersion(fileUUID: fileUUID2, db: database) else {
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
        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, appMetaData: nil, changeResolverName: CommentFile.changeResolverName)
        let declarations1 = Set<FileDeclaration>([declaration1])

        let testObject1 = ObjectDeclaration(fileGroupUUID: fileGroupUUID1, objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations1)

        func object1v0() throws {
            let uploadables:Set<FileUpload>
            
            let commentFile = CommentFile()
            let commentFileData = try commentFile.getData()
            let uploadable = FileUpload(uuid: fileUUID1, dataSource: .data(commentFileData))
            uploadables = Set<FileUpload>([uploadable])

            try syncServer.queue(uploads: uploadables, declaration: testObject1)
        }
        
        // Object2
        let declaration2 = FileDeclaration(uuid: fileUUID2, mimeType: MimeType.text, appMetaData: nil, changeResolverName: CommentFile.changeResolverName)
        let declarations2 = Set<FileDeclaration>([declaration2])

        let testObject2 = ObjectDeclaration(fileGroupUUID: fileGroupUUID2, objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations2)
        
        func object2v0() throws {
            let commentFile = CommentFile()
            let commentFileData = try commentFile.getData()
            let uploadable = FileUpload(uuid: fileUUID2, dataSource: .data(commentFileData))
            let uploadables = Set<FileUpload>([uploadable])
            try syncServer.queue(uploads: uploadables, declaration: testObject2)
        }
        
        try object1v0()
        try object2v0()
                
        // Wait for first upload instances (v0's).
        waitForUploadsToComplete(numberUploads: 2)
        
        let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        
        let uploadFileUUID:UUID
        if usingFileFromOtherDeclarationFails {
            // Using file from object1-- `queue` should fail
            uploadFileUUID = fileUUID1
        }
        else {
            uploadFileUUID = fileUUID2
        }
        
        let uploadable = FileUpload(uuid: uploadFileUUID, dataSource: .data(comment.updateContents))
        let uploadables = Set<FileUpload>([uploadable])
        
        do {
            try syncServer.queue(uploads: uploadables, declaration: testObject2)
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
        handlers.deferredCompleted = { _, operation, numberCompleted in
            XCTAssert(operation == .upload)
            XCTAssert(numberCompleted == 1)
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        XCTAssert(try UploadFileTracker.numberRows(db: database) == 0)
        XCTAssert(try UploadObjectTracker.numberRows(db: database) == 0)
        XCTAssert(try DirectoryEntry.numberRows(db: database) == 2)
    }
    
    func testRunUploadUsingFileFromOtherDeclarationFails() throws {
        try runUpload(usingFileFromOtherDeclarationFails: true)
    }
    
    func testRunUploadUsingFileFromSameDeclarationWorks() throws {
        try runUpload(usingFileFromOtherDeclarationFails: false)
    }
}
