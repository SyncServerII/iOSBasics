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

class UploadQueue_SyncTests: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests {
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
        XCTAssert(filePaths.count == 0)
    }

    // Since this uploads a vN file, it *must* use a change resolver.
    func testQueueObjectAlreadyRegisteredWorks() throws {
        let fileUUID = UUID()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        var queuedCount = 0
        uploadQueued = { _, syncObjectId in
            queuedCount += 1
        }
                        
        let declaration = FileDeclaration(uuid: fileUUID, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: CommentFile.changeResolverName)
        let declarations = Set<FileDeclaration>([declaration])

        let commentFile = CommentFile()
        let commentFileData = try commentFile.getData()
        let uploadable1 = FileUpload(uuid: fileUUID, dataSource: .data(commentFileData))
        let uploadables1 = Set<FileUpload>([uploadable1])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        try syncServer.queue(declaration: testObject, uploads: uploadables1)
        XCTAssert(queuedCount == 0)

        // This second one should work also-- but not trigger an upload-- because its for the same file group as the immediately prior `queue`. i.e., the active upload.
        let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        let uploadable2 = FileUpload(uuid: fileUUID, dataSource: .data(comment.updateContents))
        let uploadables2 = Set<FileUpload>([uploadable2])
        try syncServer.queue(declaration: testObject, uploads: uploadables2)
        // Can't do this yet due to async delegate callback.
        // XCTAssert(queuedCount == 1)

        let count = try DeclaredObjectModel.numberRows(db: database,
            where: testObject.declObjectId == DeclaredObjectModel.fileGroupUUIDField.description)
        XCTAssert(count == 1)
        
        let count2 = try DeclaredFileModel.numberRows(db: database, where: testObject.declObjectId == DeclaredFileModel.fileGroupUUIDField.description)
        XCTAssert(count2 == 1)
        
        waitForUploadsToComplete(numberUploads: 1)
        XCTAssert(queuedCount == 1)
        
        try syncServer.sync()
        waitForUploadsToComplete(numberUploads: 1, v0Upload: false)
        XCTAssert(queuedCount == 1)

        // Wait for some period of time for the deferred upload to complete.
        Thread.sleep(forTimeInterval: 5)
        
        // This `sync` is to check for deferred upload completion.
        try syncServer.sync()
        
        let exp = expectation(description: "exp")
        deferredUploadsCompleted = { _, _ in
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
    }
}

extension UploadQueue_SyncTests: SyncServerCredentials {
    func credentialsForServerRequests(_ syncServer: SyncServer) throws -> GenericCredentials {
        return user.credentials
    }
}

extension UploadQueue_SyncTests: SyncServerDelegate {
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
