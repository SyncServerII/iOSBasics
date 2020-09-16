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

class DeleteTests: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests {
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
    var deletionCompleted: ((SyncServer) -> ())?
    var deferredCompleted: ((SyncServer, DeferredOperation, _ numberCompleted: Int) -> ())?

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

    func testDeletionWithUnknownDeclaredObjectFails() throws {
        let fileUUID1 = UUID()
        let sharingGroupUUID = UUID()

        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration1])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        do {
            try syncServer.delete(object: testObject)
        } catch {
            return
        }
        XCTFail()
    }
    
    func runDeletion(withKnownDeclaredObjectButAllUnknownDeclaredFiles: Bool) throws {
        let fileUUID1 = UUID()
        let sharingGroupUUID = try getSharingGroupUUID()

        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration1])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)

        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable1])
        
        try syncServer.queue(uploads: uploadables, declaration: testObject)
        waitForUploadsToComplete(numberUploads: 1)

        let declaration2 = FileDeclaration(uuid: UUID(), mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations2 = Set<FileDeclaration>([declaration2])
        
        let testObject2 = ObjectDeclaration(fileGroupUUID: testObject.fileGroupUUID, objectType: testObject.objectType, sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations2)
        
        let object: ObjectDeclaration
        if withKnownDeclaredObjectButAllUnknownDeclaredFiles {
            object = testObject2
        }
        else {
            object = testObject
        }
        
        do {
            try syncServer.delete(object: object)
        } catch let error {
            if !withKnownDeclaredObjectButAllUnknownDeclaredFiles {
                XCTFail("\(error)")
            }
            return
        }
        
        if withKnownDeclaredObjectButAllUnknownDeclaredFiles {
            XCTFail()
            return
        }

        let exp = expectation(description: "exp")
        deletionCompleted = { _ in
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        // Wait for some period of time for the deferred deletion to complete.
        Thread.sleep(forTimeInterval: 5)

        // This `sync` is to trigger the check for the deferred upload completion.
        try syncServer.sync()

        let exp2 = expectation(description: "exp2")
        deferredCompleted = { _, operation, count in
            XCTAssert(operation == .deletion)
            XCTAssert(count == 1)
            exp2.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        // Ensure that the DirectoryEntry for the file is marked as deleted.
        guard let entry = try DirectoryEntry.fetchSingleRow(db: database, where: DirectoryEntry.fileUUIDField.description == fileUUID1) else {
            XCTFail()
            return
        }
        
        XCTAssert(entry.deletedLocally)
        XCTAssert(entry.deletedOnServer)
    }
    
    func testDeletionWithKnownDeclaredObjectButAllUnknownDeclaredFilesFails() throws {
        try runDeletion(withKnownDeclaredObjectButAllUnknownDeclaredFiles: true)
    }
    
    func testDeletionWithKnownDeclaredObjectWorks() throws {
        try runDeletion(withKnownDeclaredObjectButAllUnknownDeclaredFiles: false)
    }
    
    func testDeletionWithKnownDeclaredObjectButFewerDeclaredFilesFails() {
    }
    
    func testDeletionWithKnownDeclaredObjectButAdditionalDeclaredFilesFails() {
    }
    
    func testDeletionOfAlreadyDeletedFails() {
    }
}

extension DeleteTests: SyncServerCredentials {
    func credentialsForServerRequests(_ syncServer: SyncServer) throws -> GenericCredentials {
        return user.credentials
    }
}

extension DeleteTests: SyncServerDelegate {
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
        deferredCompleted?(syncServer, operation, numberCompleted)
    }
    
    func deletionCompleted(_ syncServer: SyncServer) {
        deletionCompleted?(syncServer)
    }
    
    func downloadDeletion(_ syncServer: SyncServer, details: DownloadDeletion) {
    }
}
