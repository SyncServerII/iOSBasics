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

class UploadQueueTests_Sync: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests {
    var deviceUUID: UUID!
    var hashingManager: HashingManager!
    var uploadCompletedHandler: ((Swift.Result<UploadFileResult, Error>) -> ())?
    var downloadCompletedHandler: ((Swift.Result<DownloadFileResult, Error>) -> ())?
    
    var api: ServerAPI!
    var syncServer: SyncServer!
    
    var uploadQueued: ((SyncServer, _ syncObjectId: UUID) -> ())?
    var uploadStarted: ((SyncServer, _ deferredUploadId:Int64) -> ())?
    var uploadCompleted: ((SyncServer, UploadFileResult) -> ())?
    var error:((SyncServer, Error?) -> ())?
    var deferredUploadsCompleted: ((SyncServer, _ count: Int)-> ())?
    
    var user: TestUser!
    var database: Connection!
    var config:Configuration!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        user = try dropboxUser()
        deviceUUID = UUID()
        database = try Connection(.inMemory)
        hashingManager = HashingManager()
        try hashingManager.add(hashing: user.hashing)
        let serverURL = URL(string: Self.baseURL())!
        config = Configuration(appGroupIdentifier: nil, sqliteDatabasePath: "", serverURL: serverURL, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, configuration: config)
        api = syncServer.api
        uploadQueued = nil
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        _ = user.removeUser()
        guard user.addUser() else {
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
        let sharingGroupUUID = try getSharingGroupUUID()

        var queuedCount = 0
        uploadQueued = { _, syncObjectId in
            queuedCount += 1
        }
        
        let declaration = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: CommentFile.changeResolverName)
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

            try syncServer.queue(declaration: testObject, uploads: uploadables)
        }
        
        var count = 0
        uploadQueued = { _, _ in
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
        XCTAssert(count == 1)

        // Wait for some period of time for the deferred upload to complete.
        Thread.sleep(forTimeInterval: 5)

        // This `sync` is to trigger the check for the deferred upload completion.
        try syncServer.sync()

        let exp = expectation(description: "exp")
        deferredUploadsCompleted = { _, _ in
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)

        XCTAssert(try UploadFileTracker.numberRows(db: database) == 0)
        XCTAssert(try UploadObjectTracker.numberRows(db: database) == 0)
        XCTAssert(try DirectoryEntry.numberRows(db: database) == 1)
    }
}

extension UploadQueueTests_Sync: SyncServerCredentials {
    func credentialsForServerRequests(_ syncServer: SyncServer) throws -> GenericCredentials {
        return user.credentials
    }
}

extension UploadQueueTests_Sync: SyncServerDelegate {
    func error(_ syncServer: SyncServer, error: Error?) {
        XCTFail("\(String(describing: error))")
        self.error?(syncServer, error)
    }

    func syncCompleted(_ syncServer: SyncServer) {
    }
    
    func downloadCompleted(_ syncServer: SyncServer, declObjectId: UUID) {
    }
    
    // A uuid that was initially generated on the client
    func uuidCollision(_ syncServer: SyncServer, type: UUIDCollisionType, from: UUID, to: UUID) {
    }
    
    func uploadQueued(_ syncServer: SyncServer, declObjectId: UUID) {
        self.uploadQueued?(syncServer, declObjectId)
    }
    
    func uploadStarted(_ syncServer: SyncServer, deferredUploadId:Int64) {
        uploadStarted?(syncServer, deferredUploadId)
    }
    
    func uploadCompleted(_ syncServer: SyncServer, result: UploadFileResult) {
        uploadCompleted?(syncServer, result)
    }
    
    func deferredUploadsCompleted(_ syncServer: SyncServer, numberCompleted: Int) {
        deferredUploadsCompleted?(syncServer, numberCompleted)
    }
}