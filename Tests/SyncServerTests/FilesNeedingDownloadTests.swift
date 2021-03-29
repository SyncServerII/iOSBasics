//
//  FilesNeedingDownloadTests.swift
//  SyncServerTests
//
//  Created by Christopher G Prince on 9/12/20.
//

import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn
import ChangeResolvers
@testable import TestsCommon

class FilesNeedingDownloadTests: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, SyncServerTests, Delegate {
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
        config = Configuration(appGroupIdentifier: nil, serverURL: serverURL, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true, deferredCheckInterval: nil)
        fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, requestable: FakeRequestable(), configuration: config, signIns: fakeSignIns, backgroundAsssertable: MainAppBackgroundTask())
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
        XCTAssert(filePaths.count == 0, "\(filePaths.count); path: \(config.temporaryFiles.directory.path)")
    }

    func testFilesNeedingDownloadUnknownSharingGroupFails() {
        do {
            _ = try syncServer.objectsNeedingDownload(sharingGroupUUID: UUID())
        } catch {
            return
        }
        XCTFail()
    }
    
    func testFilesNeedingDownloadKnownSharingGroupWorks() throws {
        let sharingGroupUUID = try syncToGetSharingGroupUUID()
        
        let files = try syncServer.objectsNeedingDownload(sharingGroupUUID: sharingGroupUUID)
        XCTAssert(files.count == 0)
    }
    
    func testFilesNeedingDownloadSingleUploadedFileWorks() throws {
        let sharingGroupUUID = try syncToGetSharingGroupUUID()
        
        _ = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID)
        
        let files = try syncServer.objectsNeedingDownload(sharingGroupUUID: sharingGroupUUID)
        XCTAssert(files.count == 0)
    }
    
    func testFilesNeedingDownloadSingleFileNeedingDownloadWorks() throws {
        let sharingGroupUUID = try syncToGetSharingGroupUUID()
        let fileUUID1 = UUID()
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)

        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .copy(exampleTextFileURL), uuid: fileUUID1)
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: [file1])
        
        try syncServer.queue(upload: upload)
        waitForUploadsToComplete(numberUploads: 1)
        
        // Reset the database show a state *as if* another client instance had done the upload-- and show the upload as ready for download.
        database = try Connection(.inMemory)
        let fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, requestable: FakeRequestable(), configuration: config, signIns: fakeSignIns, backgroundAsssertable: MainAppBackgroundTask())
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        syncServer.helperDelegate = self
        handlers.objectType = { _, _ in
            return nil
        }
        
        // It's as if the app restarted-- need to re-register the object type.
        try syncServer.register(object: example)

        try sync(withSharingGroupUUID:sharingGroupUUID)
        
        let downloadables = try syncServer.objectsNeedingDownload(sharingGroupUUID: sharingGroupUUID)
        
        guard downloadables.count == 1 else {
            XCTFail("\(downloadables.count)")
            return
        }
        
        let downloadable = downloadables[0]
        XCTAssert(upload == downloadable)
        guard downloadable.downloads.count == 1 else {
            XCTFail()
            return
        }
        
        guard let download = downloadable.downloads.first else {
            XCTFail()
            return
        }
        
        XCTAssert(download.fileVersion == 0)
        XCTAssert(download.uuid == fileUUID1)
    }
    
    func testTwoFilesNeedingDownloadInSameFileGroupWorks() throws {
        let sharingGroupUUID = try syncToGetSharingGroupUUID()
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()
        let objectType = "Foo"
        
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let fileDeclaration2 = FileDeclaration(fileLabel: "file2", mimeTypes: [.text], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1, fileDeclaration2])
        try syncServer.register(object: example)

        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .copy(exampleTextFileURL), uuid: fileUUID1)
        let file2 = FileUpload(fileLabel: fileDeclaration2.fileLabel, dataSource: .copy(exampleTextFileURL), uuid: fileUUID2)
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: [file1, file2])
                
        try syncServer.queue(upload: upload)
        waitForUploadsToComplete(numberUploads: 2)
        
        // Reset the database to a state *as if* another client instance had done the upload-- and show the upload as ready for download.
        database = try Connection(.inMemory)
        let fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, requestable: FakeRequestable(), configuration: config, signIns: fakeSignIns, backgroundAsssertable: MainAppBackgroundTask())
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        syncServer.helperDelegate = self
        
        try syncServer.register(object: example)
        
        try sync(withSharingGroupUUID:sharingGroupUUID)
        
        let downloadables = try syncServer.objectsNeedingDownload(sharingGroupUUID: sharingGroupUUID)
        
        // Single declared *object*
        guard downloadables.count == 1 else {
            XCTFail("\(downloadables.count)")
            return
        }
        
        let downloadable = downloadables[0]
        XCTAssert(upload == downloadable)
        
        // Two files needing download within that object declaration.
        guard downloadable.downloads.count == 2 else {
            XCTFail()
            return
        }

        let downloadableFile1 = downloadable.downloads.filter {$0.uuid == fileUUID1 && $0.fileVersion == 0}
        XCTAssert(downloadableFile1.count == 1)
        
        let downloadableFile2 = downloadable.downloads.filter {$0.uuid == fileUUID2 && $0.fileVersion == 0}
        XCTAssert(downloadableFile2.count == 1)
    }
    
    func testTwoFilesNeedingDownloadInDifferentFileGroupWorks() throws {
        let sharingGroupUUID = try syncToGetSharingGroupUUID()
        let fileGroupUUID1 = UUID()
        let fileGroupUUID2 = UUID()
        let objectType = "Foo"
        
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        func queue(fileGroupUUID: UUID) throws -> UUID {
            let fileUUID1 = UUID()

            let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .copy(exampleTextFileURL), uuid: fileUUID1)
            let upload = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: [file1])
            
            try syncServer.queue(upload: upload)
            waitForUploadsToComplete(numberUploads: 1)
            
            return fileUUID1
        }
        
        let fileUUID1 = try queue(fileGroupUUID: fileGroupUUID1)
        let fileUUID2 = try queue(fileGroupUUID: fileGroupUUID2)

        // Reset the database to a state *as if* another client instance had done the upload-- and show the upload as ready for download.
        database = try Connection(.inMemory)
        let fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, requestable: FakeRequestable(), configuration: config, signIns: fakeSignIns, backgroundAsssertable: MainAppBackgroundTask())
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        syncServer.helperDelegate = self
        
        try syncServer.register(object: example)
        
        try sync(withSharingGroupUUID:sharingGroupUUID)
        
        let downloadables = try syncServer.objectsNeedingDownload(sharingGroupUUID: sharingGroupUUID)
        
        guard downloadables.count == 2 else {
            XCTFail()
            return
        }
        
        let results1 = downloadables.filter {$0.fileGroupUUID == fileGroupUUID1}
        guard results1.count == 1 else {
            XCTFail()
            return
        }
        
        let file1 = results1[0].downloads.filter {$0.uuid == fileUUID1 && $0.fileVersion == 0}
        XCTAssert(file1.count == 1)
        
        let results2 = downloadables.filter {$0.fileGroupUUID == fileGroupUUID2}
        guard results2.count == 1 else {
            XCTFail()
            return
        }

        let file2 = results2[0].downloads.filter {$0.uuid == fileUUID2 && $0.fileVersion == 0}
        XCTAssert(file2.count == 1)
    }
    
    func testTwoFilesNeedingDownloadMarkFilesAsDownloaded() throws {
        let sharingGroupUUID = try syncToGetSharingGroupUUID()

        let fileGroupUUID1 = UUID()
        let fileGroupUUID2 = UUID()
        let objectType = "Foo"
        
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        func queue(fileGroupUUID: UUID) throws -> UUID {
            let fileUUID1 = UUID()

            let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .copy(exampleTextFileURL), uuid: fileUUID1)
            let upload = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: [file1])
            
            try syncServer.queue(upload: upload)
            waitForUploadsToComplete(numberUploads: 1)
            
            return fileUUID1
        }
        
        let fileUUID1 = try queue(fileGroupUUID: fileGroupUUID1)
        let fileUUID2 = try queue(fileGroupUUID: fileGroupUUID2)

        // Reset the database to a state *as if* another client instance had done the upload-- and show the upload as ready for download.
        database = try Connection(.inMemory)
        let fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, requestable: FakeRequestable(), configuration: config, signIns: fakeSignIns, backgroundAsssertable: MainAppBackgroundTask())
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        syncServer.helperDelegate = self
        
        try syncServer.register(object: example)
        
        try sync(withSharingGroupUUID:sharingGroupUUID)
        
        let downloadables = try syncServer.objectsNeedingDownload(sharingGroupUUID: sharingGroupUUID)
        
        guard downloadables.count == 2 else {
            XCTFail()
            return
        }
        
        let downloadable1 = FileToDownload(uuid: fileUUID1, fileVersion: 0)
        try syncServer.markAsDownloaded(file: downloadable1)
        
        let downloadables2 = try syncServer.objectsNeedingDownload(sharingGroupUUID: sharingGroupUUID)
        
        guard downloadables2.count == 1 else {
            XCTFail()
            return
        }
        
        guard downloadables2[0].downloads.count == 1 else {
            XCTFail()
            return
        }
        
        guard let download = downloadables2[0].downloads.first else {
            XCTFail()
            return
        }
        
        guard download.uuid == fileUUID2 else {
            XCTFail()
            return
        }

        let downloadable2 = FileToDownload(uuid: fileUUID2, fileVersion: 0)
        try syncServer.markAsDownloaded(file: downloadable2)
        
        let downloadables3 = try syncServer.objectsNeedingDownload(sharingGroupUUID: sharingGroupUUID)
        
        guard downloadables3.count == 0 else {
            XCTFail()
            return
        }
    }
    
    func runTestObjectNeedsDownload(knownFileGroup: Bool) throws {
        let sharingGroupUUID = try syncToGetSharingGroupUUID()

        let fileGroupUUID = UUID()
        
        if knownFileGroup {
            let objectType = "Foo"
            
            let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
            let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
            try syncServer.register(object: example)
            
            let fileUUID1 = UUID()

            let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .copy(exampleTextFileURL), uuid: fileUUID1)
            let upload = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: [file1])
            
            try syncServer.queue(upload: upload)
            waitForUploadsToComplete(numberUploads: 1)
        }
        
        do {
            let object = try syncServer.objectNeedsDownload(fileGroupUUID: fileGroupUUID)
            if knownFileGroup {
                XCTAssert(object == nil)
            }
        } catch let error {
            if knownFileGroup {
                XCTFail("\(error)")
            }
            return
        }
        
        if !knownFileGroup {
            XCTFail()
        }
    }
    
    // objectNeedsDownload for unknown/known file group (doesn't need download in the known case)
    func testObjectNeedsDownloadKnownFileGroupWorks() throws {
        try runTestObjectNeedsDownload(knownFileGroup: true)
    }
    
    func testObjectNeedsDownloadUnknownFileGroupFails() throws {
        try runTestObjectNeedsDownload(knownFileGroup: false)
    }
    
    func runTestObjectNeedsDownload(fileGroupNeedsDownload: Bool) throws {
        let sharingGroupUUID = try syncToGetSharingGroupUUID()

        let fileGroupUUID = UUID()
        let objectType = "Foo"
        
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let fileUUID1 = UUID()

        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .copy(exampleTextFileURL), uuid: fileUUID1)
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: [file1])
        
        try syncServer.queue(upload: upload)
        waitForUploadsToComplete(numberUploads: 1)
        
        if fileGroupNeedsDownload {
            // Reset the database to a state *as if* another client instance had done the upload-- and show the upload as ready for download.
            database = try Connection(.inMemory)
            let fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
            let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
            syncServer = try SyncServer(hashingManager: hashingManager, db: database, requestable: FakeRequestable(), configuration: config, signIns: fakeSignIns, backgroundAsssertable: MainAppBackgroundTask())
            syncServer.delegate = self
            syncServer.credentialsDelegate = self
            syncServer.helperDelegate = self
            
            try syncServer.register(object: example)
            
            try sync(withSharingGroupUUID:sharingGroupUUID)
        }
        
        let object = try syncServer.objectNeedsDownload(fileGroupUUID: fileGroupUUID)
        
        if fileGroupNeedsDownload {
            guard let object = object else {
                XCTFail()
                return
            }
            
            XCTAssert(object.fileGroupUUID == fileGroupUUID)
            XCTAssert(object.sharingGroupUUID == sharingGroupUUID)
            guard object.downloads.count == 1 else {
                XCTFail()
                return
            }
            
            XCTAssert(object.downloads[0].fileLabel == fileDeclaration1.fileLabel)
            XCTAssert(object.downloads[0].fileVersion == 0)
            XCTAssert(object.downloads[0].uuid == fileUUID1)
        }
        else {
            XCTAssert(object == nil)
        }
    }
    
    // objectNeedsDownload for file group that does/doesn't need download. (File group is always known)
    func testObjectNeedsDownloadFileGroupNeedsDownload() throws {
        try runTestObjectNeedsDownload(fileGroupNeedsDownload: true)
    }
    
    func testObjectNeedsDownloadFileGroupDoesNotNeedDownload() throws {
        try runTestObjectNeedsDownload(fileGroupNeedsDownload: false)
    }
    
    // objectNeedsDownload for file group that is being downloaded/not being downloaded (but needs download).
    func testObjectNeedsDownloadFileGroupIsBeingDownloaded() throws {
        let sharingGroupUUID = try syncToGetSharingGroupUUID()

        let fileGroupUUID = UUID()
        let objectType = "Foo"
        
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let fileUUID1 = UUID()

        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .copy(exampleTextFileURL), uuid: fileUUID1)
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: [file1])
        
        try syncServer.queue(upload: upload)
        
        let object1 = try syncServer.objectNeedsDownload(fileGroupUUID: fileGroupUUID)
        // Doesn't need download because it's being uploaded.
        XCTAssert(object1 == nil)
        
        waitForUploadsToComplete(numberUploads: 1)
        
        let object2 = try syncServer.objectNeedsDownload(fileGroupUUID: fileGroupUUID)
        // Doesn't need download because there's no new version
        XCTAssert(object2 == nil)
        
        // Reset the database to a state *as if* another client instance had done the upload-- and show the upload as ready for download.
        database = try Connection(.inMemory)
        let fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, requestable: FakeRequestable(), configuration: config, signIns: fakeSignIns, backgroundAsssertable: MainAppBackgroundTask())
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        syncServer.helperDelegate = self
        
        try syncServer.register(object: example)
        
        try sync(withSharingGroupUUID:sharingGroupUUID)
        
        let object3 = try syncServer.objectNeedsDownload(fileGroupUUID: fileGroupUUID)
        // Need downloads because the object is effectively new to us; not yet downloaded.
        XCTAssert(object3 != nil)
        
        let downloadable1 = FileToDownload(uuid: fileUUID1, fileVersion: 0)
        let downloadables = [downloadable1]
        let downloadObject = ObjectToDownload(fileGroupUUID: fileGroupUUID, downloads: downloadables)
        try syncServer.queue(download: downloadObject)
        
        let object4 = try syncServer.objectNeedsDownload(fileGroupUUID: fileGroupUUID)
        // Doesn't need downloading b/c it's in progress, downloading
        XCTAssert(object4 == nil)

        let exp = expectation(description: "exp")
        handlers.extras.downloadCompleted = { _, result in
            switch result.downloadType {
            case .gone:
                XCTFail()
                
            case .success(localFile: let url):
                // Need to cleanup and remove this file or we'll fail the test in teardown.
                try? FileManager.default.removeItem(at: url)
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        
        try syncServer.markAsDownloaded(object: downloadObject)
        
        let object5 = try syncServer.objectNeedsDownload(fileGroupUUID: fileGroupUUID)
        // Doesn't need downloading b/c it's already been downloaded.
        XCTAssert(object5 == nil)
    }
    
    func testObjectDoesNotNeedDownloadAfterLocalDeletion() throws {
        let sharingGroupUUID = try syncToGetSharingGroupUUID()

        let fileGroupUUID = UUID()
        let objectType = "Foo"
        
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let fileUUID1 = UUID()

        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .copy(exampleTextFileURL), uuid: fileUUID1)
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: [file1])
        
        try syncServer.queue(upload: upload)
        
        waitForUploadsToComplete(numberUploads: 1)

        try syncServer.queue(objectDeletion: fileGroupUUID)

        let exp = expectation(description: "exp")
        handlers.deletionCompleted = { _, _ in
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)

        let downloadable = try syncServer.objectNeedsDownload(fileGroupUUID: fileGroupUUID)
        // Doesn't need downloading b/c it's been deleted "locally". I.e., we deleted it and didn't reset the database.
        XCTAssert(downloadable == nil)
    }
    
    func testObjectDoesNotNeedDownloadAfterRemoteDeletion() throws {
        let sharingGroupUUID = try syncToGetSharingGroupUUID()

        let fileGroupUUID = UUID()
        let objectType = "Foo"
        
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let fileUUID1 = UUID()

        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .copy(exampleTextFileURL), uuid: fileUUID1)
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: [file1])
        
        try syncServer.queue(upload: upload)
        
        waitForUploadsToComplete(numberUploads: 1)

        try syncServer.queue(objectDeletion: fileGroupUUID)

        let exp = expectation(description: "exp")
        handlers.deletionCompleted = { _, _ in
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        // Reset the database to a state *as if* another client instance had done the deletion.
        database = try Connection(.inMemory)
        let fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, requestable: FakeRequestable(), configuration: config, signIns: fakeSignIns, backgroundAsssertable: MainAppBackgroundTask())
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        syncServer.helperDelegate = self
        
        try syncServer.register(object: example)
        
        try sync(withSharingGroupUUID:sharingGroupUUID)
        
        let objects = try syncServer.objectsNeedingDownload(sharingGroupUUID: sharingGroupUUID)
        XCTAssert(objects.count == 0)
    }
}
