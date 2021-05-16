//
//  GoneTests.swift
//  SyncServerTests
//
//  Created by Christopher G Prince on 2/2/21.
//

import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn
import ChangeResolvers
@testable import TestsCommon

class GoneTests: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, SyncServerTests, Delegate {
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

    // https://github.com/SyncServerII/iOSBasics/issues/2#issuecomment-772210143
    // When file is gone (in the DirectoryFileEntry), make sure it is indicated as needing download.
    func syncDownloads(afterGone: Bool) throws {
        // Upload a file.
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let localFile = Self.exampleTextFileURL
        
        let (uploadableObject, _) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        guard uploadableObject.uploads.count == 1,
            let uploadFile = uploadableObject.uploads.first else {
            XCTFail()
            return
        }
        
        let downloadable1 = FileToDownload(uuid: uploadFile.uuid, fileVersion: 0)
        let downloadObject = ObjectToDownload(fileGroupUUID: uploadableObject.fileGroupUUID, downloads: [downloadable1])

        try syncServer.queue(download: downloadObject)

        waitForDownloadsToComplete(numberExpected: 1, expectedResult: localFile)
        
        // Sync so that we get the file version updated locally. Otherwise, `objectsNeedingDownload` will fail.
        try sync(withSharingGroupUUID: sharingGroupUUID)

        if afterGone {
            // Mark it as gone.
            guard let fileEntry = try DirectoryFileEntry.fetchSingleRow(db: database, where: DirectoryFileEntry.fileUUIDField.description == uploadFile.uuid) else {
                XCTFail()
                return
            }
            
            try fileEntry.update(setters: DirectoryFileEntry.goneReasonField.description <- GoneReason.fileRemovedOrRenamed.rawValue)
        }
        
        // See if it is indicated as needing download.
        let downloadables = try syncServer.objectsNeedingDownload(sharingGroupUUID: sharingGroupUUID, includeGone: true)
        
        if afterGone {
            guard downloadables.count == 1 else {
                XCTFail("downloadables.count: \(downloadables.count)")
                return
            }
            
            let downloadable = downloadables[0]
            guard downloadable.downloads.count == 1 else {
                XCTFail()
                return
            }
            
            let downloadFile = downloadable.downloads[0]
            XCTAssert(downloadFile.uuid == uploadFile.uuid)
        }
        else {
            XCTAssert(downloadables.count == 0)
        }
    }
    
    func testSyncDownloadsAfterGone() throws {
        try syncDownloads(afterGone: true)
    }
    
    func testSyncDownloadsAfterNotGone() throws {
        try syncDownloads(afterGone: false)
    }
}
