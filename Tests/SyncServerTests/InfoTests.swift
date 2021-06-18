//
//  InfoTests.swift
//  SyncServerTests
//
//  Created by Christopher G Prince on 6/18/21.
//

import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn
import ChangeResolvers
@testable import TestsCommon

class InfoTests: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, Delegate, SyncServerTests {
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
        let serverURL = URL(string: Self.baseURL())!
        config = Configuration(appGroupIdentifier: nil, serverURL: serverURL, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true, deferredCheckInterval: nil)
        fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, requestable: FakeRequestable(), configuration: config, signIns: fakeSignIns, backgroundAsssertable: MainAppBackgroundTask(), migrationRunner: MigrationRunnerFake())
        api = syncServer.api
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        
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
    }

    func testFileGroupAttributes_noFileGroup() throws {
        let result = try syncServer.fileGroupAttributes(forFileGroupUUID: UUID())
        XCTAssert(result == nil)
    }
    
    func testFileGroupAttributes_withFileGroup() throws {
        let fileGroupUUID = UUID()
        let objectEntry = try DirectoryObjectEntry(db: database, objectType: "Foo", fileGroupUUID: fileGroupUUID, sharingGroupUUID: UUID(), cloudStorageType: .Dropbox, deletedLocally: false, deletedOnServer: false)
        try objectEntry.insert()
        
        let fileEntry = try DirectoryFileEntry(db: database, fileUUID: UUID(), fileLabel: "One", mimeType: .text, fileGroupUUID: fileGroupUUID, fileVersion: 1, serverFileVersion: nil, deletedLocally: false, deletedOnServer: false, creationDate: Date(), updateCreationDate: true, goneReason: nil)
        try fileEntry.insert()
        
        guard let result = try syncServer.fileGroupAttributes(forFileGroupUUID: fileGroupUUID) else {
            XCTFail()
            return
        }

        guard result.files.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(result.files[0].fileLabel == fileEntry.fileLabel)
        XCTAssert(result.files[0].fileUUID == fileEntry.fileUUID)
    }
}
