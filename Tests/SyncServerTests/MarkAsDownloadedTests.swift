//
//  MarkAsDownloadedTests.swift
//  SyncServerTests
//
//  Created by Christopher G Prince on 11/17/20.
//

import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn
import ChangeResolvers
@testable import TestsCommon

class MarkAsDownloadedTests: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, Delegate, SyncServerTests {
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
        XCTAssert(filePaths.count == 0, "\(filePaths.count)")
    }

    func testMarkAsDownloadedFileWorks() throws {
        let sharingGroupUUID = try syncToGetSharingGroupUUID()
        let fileUUID1 = UUID()
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)

        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .copy(exampleTextFileURL), uuid: fileUUID1)
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
        
        try syncServer.markAsDownloaded(file: download)
        
        let downloadables2 = try syncServer.objectsNeedingDownload(sharingGroupUUID: sharingGroupUUID)
        XCTAssert(downloadables2.count == 0)
    }
    
    func testMarkAsDownloadedObjectWithOneFileWorks() throws {
        let sharingGroupUUID = try syncToGetSharingGroupUUID()
        let fileUUID1 = UUID()
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)

        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .copy(exampleTextFileURL), uuid: fileUUID1)
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
        
        let downloadObject = ObjectToDownload(fileGroupUUID: upload.fileGroupUUID, downloads: [FileToDownload(uuid: download.uuid, fileVersion: download.fileVersion)])
        
        try syncServer.markAsDownloaded(object: downloadObject)
        
        let downloadables2 = try syncServer.objectsNeedingDownload(sharingGroupUUID: sharingGroupUUID)
        XCTAssert(downloadables2.count == 0)
    }
    
    func testMarkAsDownloadedObjectWithTwoFilesWorks() throws {
        let sharingGroupUUID = try syncToGetSharingGroupUUID()
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()

        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let fileDeclaration2 = FileDeclaration(fileLabel: "file2", mimeTypes: [.text], changeResolverName: nil)

        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1, fileDeclaration2])
        try syncServer.register(object: example)

        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .copy(exampleTextFileURL), uuid: fileUUID1)
        let file2 = FileUpload(fileLabel: fileDeclaration2.fileLabel, mimeType: .text, dataSource: .copy(exampleTextFileURL), uuid: fileUUID2)
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: [file1, file2])
        
        try syncServer.queue(upload: upload)
        waitForUploadsToComplete(numberUploads: 2)
        
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
        
        guard downloadables.count == 1, downloadables[0].downloads.count == 2 else {
            XCTFail("\(downloadables.count)")
            return
        }
        
        let downloadObject = ObjectToDownload(fileGroupUUID: upload.fileGroupUUID, downloads: [
            FileToDownload(uuid: fileUUID1, fileVersion: 0),
            FileToDownload(uuid: fileUUID2, fileVersion: 0)
        ])
        
        try syncServer.markAsDownloaded(object: downloadObject)
        
        let downloadables2 = try syncServer.objectsNeedingDownload(sharingGroupUUID: sharingGroupUUID)
        XCTAssert(downloadables2.count == 0)
    }
}
