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

class DeleteTests: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, Delegate {
    var handlers = DelegateHandlers()
    var deviceUUID: UUID!
    var hashingManager: HashingManager!
    var api: ServerAPI!
    var syncServer: SyncServer!
    
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

    func testDeletionWithUnknownDeclaredObjectFails() throws {
        let fileUUID1 = UUID()
        let sharingGroupUUID = UUID()

        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration1])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        do {
            try syncServer.queue(deletion: testObject)
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
            try syncServer.queue(deletion: object)
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
    
    func runDeletionWithKnownDeclaredObject(fewerDeclaredFiles: Bool) throws {
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()

        let sharingGroupUUID = try getSharingGroupUUID()
        let fileGroupUUID = UUID()
        
        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declaration2 = FileDeclaration(uuid: fileUUID2, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)

        let object1 = ObjectDeclaration(fileGroupUUID: fileGroupUUID, objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: Set<FileDeclaration>([declaration1, declaration2]))

        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable1])
        
        try syncServer.queue(uploads: uploadables, declaration: object1)
        waitForUploadsToComplete(numberUploads: 1)

        let object2 = ObjectDeclaration(fileGroupUUID: fileGroupUUID, objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: Set<FileDeclaration>([declaration1]))
        
        let object: ObjectDeclaration
        if fewerDeclaredFiles {
            object = object2
        }
        else {
            object = object1
        }
        
        do {
            try syncServer.queue(deletion: object)
        } catch let error {
            if !fewerDeclaredFiles {
                XCTFail("\(error)")
            }
            return
        }
        
        if fewerDeclaredFiles {
            XCTFail()
            return
        }

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
        
        // Ensure that the DirectoryEntry for the file is marked as deleted.
        guard let entry = try DirectoryEntry.fetchSingleRow(db: database, where: DirectoryEntry.fileUUIDField.description == fileUUID1) else {
            XCTFail()
            return
        }
        
        XCTAssert(entry.deletedLocally)
        XCTAssert(entry.deletedOnServer)
    }
    
    func testRunDeletionWithKnownDeclaredObjectFewerDeclaredFilesFails() throws {
        try runDeletionWithKnownDeclaredObject(fewerDeclaredFiles: true)
    }
    
    func testRunDeletionWithKnownDeclaredObjectSameDeclaredFilesWorks() throws {
        try runDeletionWithKnownDeclaredObject(fewerDeclaredFiles: false)
    }
    
    func runDeletionWithKnownDeclaredObject(moreDeclaredFiles: Bool) throws {
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()

        let sharingGroupUUID = try getSharingGroupUUID()
        let fileGroupUUID = UUID()
        
        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declaration2 = FileDeclaration(uuid: fileUUID2, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)

        let object1 = ObjectDeclaration(fileGroupUUID: fileGroupUUID, objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: Set<FileDeclaration>([declaration1]))

        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable1])
        
        try syncServer.queue(uploads: uploadables, declaration: object1)
        waitForUploadsToComplete(numberUploads: 1)

        let object2 = ObjectDeclaration(fileGroupUUID: fileGroupUUID, objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: Set<FileDeclaration>([declaration1, declaration2]))
        
        let object: ObjectDeclaration
        if moreDeclaredFiles {
            object = object2
        }
        else {
            object = object1
        }
        
        do {
            try syncServer.queue(deletion: object)
        } catch let error {
            if !moreDeclaredFiles {
                XCTFail("\(error)")
            }
            return
        }
        
        if moreDeclaredFiles {
            XCTFail()
            return
        }

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
        
        // Ensure that the DirectoryEntry for the file is marked as deleted.
        guard let entry = try DirectoryEntry.fetchSingleRow(db: database, where: DirectoryEntry.fileUUIDField.description == fileUUID1) else {
            XCTFail()
            return
        }
        
        XCTAssert(entry.deletedLocally)
        XCTAssert(entry.deletedOnServer)
    }
    
    func testRunDeletionWithKnownDeclaredObjectMoreDeclaredFilesFails() throws {
        try runDeletionWithKnownDeclaredObject(moreDeclaredFiles: true)
    }
    
    func testRunDeletionWithKnownDeclaredObjectSameDeclaredFilesWorks2() throws {
        try runDeletionWithKnownDeclaredObject(moreDeclaredFiles: false)
    }
    
    func runDeletion(alreadyDeleted: Bool) throws {
        let fileUUID1 = UUID()

        let sharingGroupUUID = try getSharingGroupUUID()
        let fileGroupUUID = UUID()
        
        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)

        let object1 = ObjectDeclaration(fileGroupUUID: fileGroupUUID, objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: Set<FileDeclaration>([declaration1]))

        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable1])
        
        try syncServer.queue(uploads: uploadables, declaration: object1)
        waitForUploadsToComplete(numberUploads: 1)
        
        try syncServer.queue(deletion: object1)

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
        
        if alreadyDeleted {
            do {
                try syncServer.queue(deletion: object1)
            } catch {
                return
            }
            
            XCTFail()
        }
    }
    
    func testDeletionAlreadyDeleted() throws {
        try runDeletion(alreadyDeleted: true)
    }
    
    func testDeletionNotAlreadyDeleted() throws {
        try runDeletion(alreadyDeleted: false)
    }
}
