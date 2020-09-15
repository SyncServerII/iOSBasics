//
//  IndexTests.swift
//  SyncServerTests
//
//  Created by Christopher G Prince on 9/11/20.
//

import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn
import ChangeResolvers

class IndexTests: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests {
    var deviceUUID: UUID!
    var hashingManager: HashingManager!
    var uploadCompletedHandler: ((Swift.Result<UploadFileResult, Error>) -> ())?
    var downloadCompletedHandler: ((Swift.Result<DownloadFileResult, Error>) -> ())?
    
    var api: ServerAPI!
    var syncServer: SyncServer!
    var uploadQueued: ((SyncServer, _ syncObjectId: UUID) -> ())?
    var uploadStarted: ((SyncServer, _ deferredUploadId:Int64) -> ())?
    var uploadCompleted: ((SyncServer, UploadResult) -> ())?
    var error:((SyncServer, Error?) -> ())?
    var syncCompleted: ((SyncServer, SyncResult) -> ())?
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

    func testIndexCalledDirectly() throws {
        let sharingGroupUUID = try getSharingGroupUUID()

        let exp = expectation(description: "exp")
        
        syncCompleted = { _, result in
            guard case .index(let uuid, let index) = result else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            XCTAssert(sharingGroupUUID == uuid)
            XCTAssert(index.count == 0)
            guard let result = try? SharingEntry.fetchSingleRow(db: self.database, where: SharingEntry.sharingGroupUUIDField.description == sharingGroupUUID) else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            XCTAssert(result.sharingGroupUUID == sharingGroupUUID)
            exp.fulfill()
        }
        
        error = { _, error in
            XCTFail("\(String(describing: error))")
            exp.fulfill()
        }
        
        syncServer.getIndex(sharingGroupUUID: sharingGroupUUID)

        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testIndexCalledFromSyncServer() throws {
        let sharingGroupUUID = try getSharingGroupUUID()

        let exp = expectation(description: "exp")
        
        syncCompleted = { _, result in
            guard case .index(let uuid, let index) = result else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            XCTAssert(sharingGroupUUID == uuid)
            XCTAssert(index.count == 0)
            guard let result = try? SharingEntry.fetchSingleRow(db: self.database, where: SharingEntry.sharingGroupUUIDField.description == sharingGroupUUID) else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            XCTAssert(result.sharingGroupUUID == sharingGroupUUID)
            exp.fulfill()
        }
        
        error = { _, error in
            XCTFail()
            exp.fulfill()
        }
        
        try syncServer.sync(sharingGroupUUID: sharingGroupUUID)

        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func uploadExampleTextFile(sharingGroupUUID: UUID) throws -> ObjectDeclaration {
        let fileUUID1 = UUID()
        
        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration1])

        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable1])

        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        try syncServer.queue(declaration: testObject, uploads: uploadables)
        
        waitForUploadsToComplete(numberUploads: 1)
        
        return testObject
    }
    
    func testIndexCalledFromSyncServerWithOneFile() throws {
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let declaration = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID)
        guard declaration.declaredFiles.count == 1,
            let declaredFile = declaration.declaredFiles.first else {
            XCTFail()
            return
        }

        let exp = expectation(description: "exp")
        
        syncCompleted = { _, result in
            guard case .index(let uuid, let index) = result else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            XCTAssert(sharingGroupUUID == uuid)
            guard index.count == 1 else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            XCTAssert(declaredFile.uuid.uuidString == index[0].fileUUID)
            
            guard let result = try? SharingEntry.fetchSingleRow(db: self.database, where: SharingEntry.sharingGroupUUIDField.description == sharingGroupUUID) else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            XCTAssert(result.sharingGroupUUID == sharingGroupUUID)
            exp.fulfill()
        }
        
        error = { _, error in
            XCTFail()
            exp.fulfill()
        }
        
        try syncServer.sync(sharingGroupUUID: sharingGroupUUID)

        waitForExpectations(timeout: 10, handler: nil)
    }
}

extension IndexTests: SyncServerCredentials {
    func credentialsForServerRequests(_ syncServer: SyncServer) throws -> GenericCredentials {
        return user.credentials
    }
}

extension IndexTests: SyncServerDelegate {
    func error(_ syncServer: SyncServer, error: Error?) {
        XCTFail("\(String(describing: error))")
        self.error?(syncServer, error)
    }

    func syncCompleted(_ syncServer: SyncServer, result: SyncResult) {
        syncCompleted?(syncServer, result)
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
    
    func uploadCompleted(_ syncServer: SyncServer, result: UploadResult) {
        uploadCompleted?(syncServer, result)
    }
    
    func deferredCompleted(_ syncServer: SyncServer, operation: DeferredOperation, numberCompleted: Int) {
    }
    
    func deletionCompleted(_ syncServer: SyncServer) {
    }
}
