//
//  DownloadQueueTests_TwoObjectDeclarations.swift
//  SyncServerTests
//
//  Created by Christopher G Prince on 9/18/20.
//

import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn
@testable import TestsCommon

class DownloadQueueTests_TwoObjectDeclarations: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, Delegate, SyncServerTests {
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
        set(logLevel: .trace)
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
    }

    override func tearDownWithError() throws {
        // All temporary files should have been removed prior to end of test.
        let filePaths = try FileManager.default.contentsOfDirectory(atPath: config.temporaryFiles.directory.path)
        XCTAssert(filePaths.count == 0, "\(filePaths.count)")
    }
    
    func testUndeclaredObjectFails() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let localFile = Self.exampleTextFileURL
        
        let _ = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        
        let fileUUID1 = UUID()
        let declaration2 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, appMetaData: nil, changeResolverName: nil)
        let declarations2 = Set<FileDeclaration>([declaration2])

        let object2 = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations2)
        
        let downloadable1 = FileDownload(uuid: fileUUID1, fileVersion: 0)
        let downloadables = Set<FileDownload>([downloadable1])
        
        do {
            try syncServer.queue(downloads: downloadables, declaration: object2)
        } catch let error {
            guard let databaseModelError = error as? DatabaseModelError else {
                XCTFail()
                return
            }
            
            XCTAssert(databaseModelError == DatabaseModelError.noObject)
        }
    }

    func testQueueDownloadsFromDifferentObjectAlsoDownloads() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        let localFile = Self.exampleTextFileURL
        
        let declaration1 = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        guard declaration1.declaredFiles.count == 1,
            let declaredFile1 = declaration1.declaredFiles.first else {
            XCTFail()
            return
        }
        
        let declaration2 = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        guard declaration2.declaredFiles.count == 1,
            let declaredFile2 = declaration2.declaredFiles.first else {
            XCTFail()
            return
        }
        
        let downloadable1 = FileDownload(uuid: declaredFile1.uuid, fileVersion: 0)
        let downloadables1 = Set<FileDownload>([downloadable1])
        
        let downloadable2 = FileDownload(uuid: declaredFile2.uuid, fileVersion: 0)
        let downloadables2 = Set<FileDownload>([downloadable2])
        
        try syncServer.queue(downloads: downloadables1, declaration: declaration1)
        try syncServer.queue(downloads: downloadables2, declaration: declaration2)

        var count = 0
        
        let exp = expectation(description: "exp")
        handlers.extras.downloadCompleted = { _, result in
            count += 1
            
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
            }
            
            if count == 2 {
                exp.fulfill()
            }
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        
        XCTAssert(try DownloadFileTracker.numberRows(db: database) == 0)
        XCTAssert(try DownloadObjectTracker.numberRows(db: database) == 0)
    }
}
