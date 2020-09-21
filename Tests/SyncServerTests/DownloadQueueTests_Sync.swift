//
//  DownloadQueueTests_Sync.swift
//  SyncServerTests
//
//  Created by Christopher G Prince on 9/18/20.
//

import XCTest

import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn

class DownloadQueueTests_Sync: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, Delegate, SyncServerTests {
    var deviceUUID: UUID!
    var hashingManager: HashingManager!
    var api: ServerAPI!
    var syncServer: SyncServer!
    var handlers = DelegateHandlers()
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
        
        let count = try NetworkCache.numberRows(db: database)
        XCTAssert(count == 0, "\(count)")
    }

    func testSyncWithNoDownloadsToDoWorks() throws {
        let exp = expectation(description: "exp")
        handlers.extras.downloadSync = { _, count in
            exp.fulfill()
        }
        
        try syncServer.sync()
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testSecondDownloadOfSameObjectTriggersWithSync() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let localFile = Self.exampleTextFileURL
        
        let declaration = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        guard declaration.declaredFiles.count == 1,
            let declaredFile = declaration.declaredFiles.first else {
            XCTFail()
            return
        }
        
        let downloadable1 = FileDownload(uuid: declaredFile.uuid, fileVersion: 0)
        let downloadables = Set<FileDownload>([downloadable1])

        try syncServer.queue(downloads: downloadables, declaration: declaration)

        // This second one will be queued
        try syncServer.queue(downloads: downloadables, declaration: declaration)

        waitForDownloadsToComplete(numberExpected: 1, expectedResult: localFile)

        let exp2 = expectation(description: "exp")
        handlers.extras.downloadSync = { _, count in
            exp2.fulfill()
        }

        // Trigger the second download.
        try syncServer.sync()

        waitForExpectations(timeout: 10, handler: nil)
        
        waitForDownloadsToComplete(numberExpected: 1, expectedResult: localFile)
    }
    
    // If I call a sync too early, when an active download is happening for the same file group, no additional download happens.
    func testSyncDoesNotTriggerDownloadWhenItIsNotReady() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let localFile = Self.exampleTextFileURL
        
        let declaration = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        guard declaration.declaredFiles.count == 1,
            let declaredFile = declaration.declaredFiles.first else {
            XCTFail()
            return
        }
        
        let downloadable1 = FileDownload(uuid: declaredFile.uuid, fileVersion: 0)
        let downloadables = Set<FileDownload>([downloadable1])

        try syncServer.queue(downloads: downloadables, declaration: declaration)

        // This second one will be queued
        try syncServer.queue(downloads: downloadables, declaration: declaration)

        let exp2 = expectation(description: "exp")
        handlers.extras.downloadSync = { _, count in
            XCTAssert(count == 0)
            exp2.fulfill()
        }
        
        // This should not fail, and neither should it cause the second download to occur.
        try syncServer.sync()
        
        waitForExpectations(timeout: 10, handler: nil)

        waitForDownloadsToComplete(numberExpected: 1, expectedResult: localFile)
        
        let count1 = try DownloadFileTracker.numberRows(db: database)
        XCTAssert(count1 == 1, "\(count1)")

        let count2 = try DownloadObjectTracker.numberRows(db: database)
        XCTAssert(count2 == 1, "\(count2)")
    }
}
