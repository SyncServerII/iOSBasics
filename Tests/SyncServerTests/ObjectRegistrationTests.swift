//
//  ObjectRegistrationTests.swift
//  iOSBasics
//
//  Created by Christopher G Prince on 10/8/20.
//

import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn
import ChangeResolvers
@testable import TestsCommon

class ExampleDeclaration: DeclarableObject, ObjectDownloadHandler {    
    func getFileLabel(appMetaData: String) -> String? {
        assert(false)
        return nil
    }
    
    func objectWasDownloaded(object: DownloadObject) {
    }
    
    let declaredFiles: [DeclarableFile]
    let objectType: String
    
    init(objectType: String, declaredFiles: [DeclarableFile]) {
        self.objectType = objectType
        self.declaredFiles = declaredFiles
    }
}

class ObjectRegistrationTests: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, Delegate, SyncServerTests {
    var deviceUUID: UUID!
    var hashingManager: HashingManager!
    var uploadCompletedHandler: ((Swift.Result<UploadFileResult, Error>) -> ())?
    var downloadCompletedHandler: ((Swift.Result<DownloadFileResult, Error>) -> ())?
    var api: ServerAPI!
    var syncServer: SyncServer!
    var database: Connection!
    var config:Configuration!
    var handlers = DelegateHandlers()
    var fakeHelper:SignInServicesHelperFake!
    
    override func setUpWithError() throws {
        set(logLevel: .trace)
        handlers = DelegateHandlers()
        try super.setUpWithError()
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

    func testRegisterNewDeclarationWithNoFilesFails() throws {
        let example = ExampleDeclaration(objectType: "Foo", declaredFiles: [])
        
        do {
            try syncServer.register(object: example)
            XCTFail()
        } catch {
        }
    }
    
    func testRegisterNewDeclaration() throws {
        let count1 = syncServer.objectDeclarations.count
        let fileDeclaration = FileDeclaration(fileLabel: "file2", mimeType: .jpeg, changeResolverName: nil)

        let example = ExampleDeclaration(objectType: "Foo", declaredFiles: [fileDeclaration])
        try syncServer.register(object: example)

        guard let _ = try DeclaredObjectModel.fetchSingleRow(db: database, where: example.objectType == DeclaredObjectModel.objectTypeField.description) else {
            XCTFail()
            return
        }
        
        let count2 = syncServer.objectDeclarations.count
        XCTAssert(count2 == count1 + 1, "\(count2) != \(count1 + 1)")
        
        guard count2 == 1 else {
            XCTFail()
            return
        }
        
        guard let declaration = syncServer.objectDeclarations[example.objectType] else {
            XCTFail()
            return
        }
        
        XCTAssert(declaration.equal(example))
    }
    
    func testReRegisterObjectWithoutAllFilesFails() throws {
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "one", mimeType: .jpeg, changeResolverName: nil)
        let fileDeclaration2 = FileDeclaration(fileLabel: "two", mimeType: .jpeg, changeResolverName: nil)
        let example1 = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1, fileDeclaration2])
        try syncServer.register(object: example1)

        let example2 = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        do {
            try syncServer.register(object: example2)
            XCTFail()
        } catch {
        }
    }
    
  func testReRegisterObjectWithoutAllFilesFails2() throws {
        let objectType = "Foo"
    let fileDeclaration1 = FileDeclaration(fileLabel: "one", mimeType: .jpeg, changeResolverName: nil)
    let fileDeclaration2 = FileDeclaration(fileLabel: "two", mimeType: .jpeg, changeResolverName: "New")
        let example1 = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1, fileDeclaration2])
        try syncServer.register(object: example1)

    let fileDeclaration3 = FileDeclaration(fileLabel: "three", mimeType: .jpeg, changeResolverName: "Stew")
    let fileDeclaration4 = FileDeclaration(fileLabel: "four", mimeType: .jpeg, changeResolverName: "Blew")
        let example2 = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration3, fileDeclaration4])
        do {
            try syncServer.register(object: example2)
            XCTFail()
        } catch {
        }
    }
    
    func testRegisterSameObjectTwiceWorks() throws {
        let count1 = syncServer.objectDeclarations.count
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "one", mimeType: .jpeg, changeResolverName: nil)
        let example1 = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example1)

        let count2 = syncServer.objectDeclarations.count
        XCTAssert(count1 + 1 == count2, "\(count1 + 1) != \(count2)")
        
        let example2 = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example2)
        
        // It was the same object-- no new object gets registered
        let count3 = syncServer.objectDeclarations.count
        XCTAssert(count2 == count3, "\(count2) != \(count3)")
        
        guard syncServer.objectDeclarations.count == 1 else {
            XCTFail()
            return
        }
        
        guard let declaration = syncServer.objectDeclarations[objectType] else {
            XCTFail()
            return
        }
        
        XCTAssert(declaration.equal(example2))
    }
     
    func testRegisterAddsNewFileWorks() throws {
        let count1 = syncServer.objectDeclarations.count
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "one", mimeType: .jpeg, changeResolverName: nil)
        let example1 = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example1)
        
        let count2 = syncServer.objectDeclarations.count
        XCTAssert(count1 + 1 == count2, "\(count1 + 1) != \(count2)")

        let fileDeclaration2 = FileDeclaration(fileLabel: "two", mimeType: .jpeg, changeResolverName: nil)
        let example2 = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1, fileDeclaration2])
        try syncServer.register(object: example2)
        
        // It was the same object-- no new object gets registered
        let count3 = syncServer.objectDeclarations.count
        XCTAssert(count2 == count3, "\(count2) != \(count3)")
        
        guard syncServer.objectDeclarations.count == 1 else {
            XCTFail()
            return
        }
        
        guard let declaration = syncServer.objectDeclarations[objectType] else {
            XCTFail()
            return
        }
        
        XCTAssert(declaration.equal(example2))
    }
    
    func runRegister(duplicateFileLabel: Bool) throws {
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "one", mimeType: .jpeg, changeResolverName: nil)
        let fileDeclaration2 = FileDeclaration(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, changeResolverName: nil)

        var files = [fileDeclaration2]
        
        if duplicateFileLabel {
            files += [fileDeclaration1]
        }
        
        let example1 = ExampleDeclaration(objectType: objectType, declaredFiles: files)
        
        do {
            try syncServer.register(object: example1)
        } catch {
            if !duplicateFileLabel {
                XCTFail()
            }
            return
        }
        
        if duplicateFileLabel {
            XCTFail()
        }
    }
    
    func testRegisterWithDuplicateFileLabelFails() throws {
        try runRegister(duplicateFileLabel: true)
    }
    
    func testRegisterWithNoDuplicateFileLabelWorks() throws {
        try runRegister(duplicateFileLabel: false)
    }
    
    func testRegisterMultipleObjectTypesWorks() throws {
        let objectType1 = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "one", mimeType: .text, changeResolverName: nil)
        let files1 = [fileDeclaration1]
        let example1 = ExampleDeclaration(objectType: objectType1, declaredFiles: files1)
        try syncServer.register(object: example1)
        
        let objectType2 = "Foo2"
        let fileDeclaration2 = FileDeclaration(fileLabel: "one", mimeType: .text, changeResolverName: nil)
        let files2 = [fileDeclaration2]
        let example2 = ExampleDeclaration(objectType: objectType2, declaredFiles: files2)
        try syncServer.register(object: example2)
    }
}
