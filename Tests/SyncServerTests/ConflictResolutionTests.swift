//
//  ConflictResolutionTests.swift
//  iOSBasicsTests
//
//  Created by Christopher G Prince on 9/14/20.
//

import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn
import ChangeResolvers

class ConflictResolutionTests: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, Delegate {
    var deviceUUID: UUID!
    var hashingManager: HashingManager!
    var uploadCompletedHandler: ((Swift.Result<UploadFileResult, Error>) -> ())?
    var downloadCompletedHandler: ((Swift.Result<DownloadFileResult, Error>) -> ())?
    
    var api: ServerAPI!
    var syncServer: SyncServer!

    var database: Connection!
    var config:Configuration!
    var handlers = DelegateHandlers()
    
    override func setUpWithError() throws {
        handlers = DelegateHandlers()
        try super.setUpWithError()
        handlers.user = try dropboxUser()
        deviceUUID = UUID()
        database = try Connection(.inMemory)
        hashingManager = HashingManager()
        try hashingManager.add(hashing: handlers.user.hashing)
        let serverURL = URL(string: Self.baseURL())!
        config = Configuration(appGroupIdentifier: nil, sqliteDatabasePath: "", serverURL: serverURL, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, configuration: config)
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
    
    // https://github.com/SyncServerII/ServerMain/issues/7

    func testDeletionAfterServerDeletionDoesNotFail() throws {
        let fileUUID1 = UUID()
        let sharingGroupUUID = try getSharingGroupUUID()

        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration1])
        
        let object = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)

        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable1])
        
        try syncServer.queue(uploads: uploadables, declaration: object)
        waitForUploadsToComplete(numberUploads: 1)
        
        try syncServer.queue(deletion: object)

        let exp = expectation(description: "exp")
        handlers.deletionCompleted = { _ in
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        // Wait for some period of time for the deferred deletion to complete.
        Thread.sleep(forTimeInterval: 5)

        // This `sync` is to trigger the check for the deferred upload completion.
        try syncServer.sync()

        let exp2 = expectation(description: "exp2")
        handlers.deferredCompleted = { _, operation, count in
            XCTAssert(operation == .deletion)
            XCTAssert(count == 1)
            exp2.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        // Now, file is deleted on server. Cheat and mark our directory entry as non-deleted.
        
        guard let entry = try DirectoryEntry.fetchSingleRow(db: database, where: DirectoryEntry.fileUUIDField.description == fileUUID1) else {
            XCTFail()
            return
        }
        
        try entry.update(setters:
            DirectoryEntry.deletedLocallyField.description <- false,
            DirectoryEntry.deletedOnServerField.description <- false)

        let exp3 = expectation(description: "exp")
        handlers.deletionCompleted = { _ in
            exp3.fulfill()
        }
        
        // Note that this second delete works "out of the box" despite of the fact that we fooled ourselves (locally) into believing the file was not deleted. The server allows multiple deletions with no ill effect. (The second deletion does nothing).
        try syncServer.queue(deletion: object)
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testUploadAfterServerDeletionDoesNotFail() throws {
        let fileUUID1 = UUID()
        let fileGroupUUID1 = UUID()
        let sharingGroupUUID = try getSharingGroupUUID()

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

            try syncServer.queue(uploads: uploadables, declaration: testObject)
        }
        
        try object1(v0: true)
        waitForUploadsToComplete(numberUploads: 1)
        
        // v0 file uploaded.
        
        // Let's delete it.
        
        try syncServer.queue(deletion: testObject)

        let exp = expectation(description: "exp")
        handlers.deletionCompleted = { _ in
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        // Wait for some period of time for the deferred deletion to complete.
        Thread.sleep(forTimeInterval: 5)

        // This `sync` is to trigger the check for the deferred upload completion.
        try syncServer.sync()

        let exp2 = expectation(description: "exp2")
        handlers.deferredCompleted = { _, operation, count in
            XCTAssert(operation == .deletion)
            XCTAssert(count == 1)
            exp2.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        // Now, file is deleted on server. Cheat and mark our directory entry as non-deleted.
        
        guard let entry = try DirectoryEntry.fetchSingleRow(db: database, where: DirectoryEntry.fileUUIDField.description == fileUUID1) else {
            XCTFail()
            return
        }
        
        try entry.update(setters:
            DirectoryEntry.deletedLocallyField.description <- false,
            DirectoryEntry.deletedOnServerField.description <- false)

        try object1(v0: false)
        waitForUploadsToComplete(numberUploads: 1, gone: true)
    }
}
