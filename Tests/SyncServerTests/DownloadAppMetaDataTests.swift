//
//  DownloadAppMetaDataTests.swift
//  SyncServerTests
//
//  Created by Christopher G Prince on 5/8/21.
//

import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn
@testable import TestsCommon

class DownloadAppMetaDataTests: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, Delegate, SyncServerTests {
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
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, requestable: FakeRequestable(), configuration: config, signIns: fakeSignIns, backgroundAsssertable: MainAppBackgroundTask(), migrationRunner: MigrationRunnerFake())
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

    func testDownloadAppMetaData() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let localFile = Self.exampleTextFileURL
        
        let fileUUID1 = UUID()
        let objectType: String = "Foo"
        let appMetaData = "Example app meta data"
        
        var downloadedAppMetaData: String?
        
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1], objectWasDownloaded: { downloadedObject in
            guard downloadedObject.downloads.count == 1 else {
                XCTFail()
                return
            }
            
            let download = downloadedObject.downloads[0]
            downloadedAppMetaData = download.appMetaData
            XCTAssert(downloadedAppMetaData == appMetaData)
        })
        
        try syncServer.register(object: example)
                
        let fileUpload1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .copy(localFile), uuid: fileUUID1, appMetaData: appMetaData)
        
        let uploadableObject = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload1])
        
        try syncServer.queue(upload: uploadableObject)
                
        waitForUploadsToComplete(numberUploads: 1)
        
        guard uploadableObject.uploads.count == 1,
            let uploadableFile = uploadableObject.uploads.first else {
            XCTFail()
            return
        }
        
        let downloadable1 = FileToDownload(uuid: uploadableFile.uuid, fileVersion: 0)
        
        let downloadObject = ObjectToDownload(fileGroupUUID: uploadableObject.fileGroupUUID, downloads: [downloadable1])

        try syncServer.queue(download: downloadObject)

        let exp = expectation(description: "exp")
        handlers.extras.downloadCompleted = { _, result in
            switch result.downloadType {
            case .gone:
                XCTFail()
                
            case .success(let url):
                do {
                    let data1 = try Data(contentsOf: localFile)
                    let data2 = try Data(contentsOf: url)
                    XCTAssert(data1 == data2)
                    try FileManager.default.removeItem(at: url)
                } catch {
                    XCTFail()
                }
                
                XCTAssert(result.appMetaData == appMetaData)
                XCTAssert(downloadedAppMetaData != nil)
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        
        XCTAssert(try DownloadFileTracker.numberRows(db: database) == 0)
        XCTAssert(try DownloadObjectTracker.numberRows(db: database) == 0)
    }
}
