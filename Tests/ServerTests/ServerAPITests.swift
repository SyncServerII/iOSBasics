//
//  ServerAPITests.swift
//  iOSBasicsTests
//
//  Created by Christopher G Prince on 5/17/20.
//

import XCTest
@testable import iOSBasics
import iOSSignIn
@testable import iOSDropbox
import ServerShared
import iOSShared
import SQLite

class ServerAPITests: XCTestCase, UserSetup, APITests, ServerAPIDelegator, ServerBasics, TestFiles {
    var hashingManager: HashingManager!
    var uploadCompletedHandler: ((Swift.Result<UploadFileResult, Error>) -> ())?
    var downloadCompletedHandler: ((Swift.Result<DownloadFileResult, Error>) -> ())?
    var api: ServerAPI!
    var deviceUUID: UUID!
    var user: TestUser!
    var database: Connection!
    let config = Configuration.defaultTemporaryFiles
    var error:((SyncServer, Error?) -> ())?
    var uploadCompleted: ((SyncServer, UploadFileResult) -> ())?
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        uploadCompletedHandler = nil
        user = try dropboxUser()
        deviceUUID = UUID()
        let database = try Connection(.inMemory)
        try NetworkCache.createTable(db: database)
        let config = Configuration(appGroupIdentifier: nil, sqliteDatabasePath: "", serverURL: URL(string: Self.baseURL())!, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true)
        hashingManager = HashingManager()
        try? hashingManager.add(hashing: DropboxHashing())
        api = ServerAPI(database: database, hashingManager: hashingManager, delegate: self, config: config)
        _ = user.removeUser()
        XCTAssert(user.addUser())
    }

    override func tearDownWithError() throws {
    }

    func testHealthCheck() throws {
        let exp = expectation(description: "exp")

        api.healthCheck { result in
            switch result {
            case .success(let response):
                XCTAssert(response.currentServerDateTime != nil)
            case .failure:
                XCTFail()
            }
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testAddUser() {
        _ = user.removeUser()
        XCTAssert(user.addUser())
    }
    
    func testCheckCredsWithAUser() {
        _ = user.removeUser()
        XCTAssert(user.addUser())
        
        let result = checkCreds()
        
        switch result {
        case .some(.user):
            break
        default:
            XCTFail()
        }
    }
    
    func testCheckCredsWithNoUser() {
        // Get ready for test.
        guard user.removeUser() else {
            XCTFail()
            return
        }
        
        let result = checkCreds()
        
        switch result {
        case .some(.noUser):
            break
        default:
            XCTFail()
        }
    }
    
    func testIndexWithNoContentsExpectation() {
        _ = user.removeUser()
        XCTAssert(user.addUser())
        
        guard let result = getIndex(sharingGroupUUID: nil) else {
            XCTFail()
            return
        }
        
        XCTAssert(result.fileIndex == nil)
        XCTAssert(result.sharingGroups.count == 1)
    }
    
    func testIndexWithFile() throws {
        _ = user.removeUser()
        XCTAssert(user.addUser())
        
        let fileUUID = UUID()
        let fileURL = exampleTextFileURL
        
        let hashing = try hashingManager.hashFor(cloudStorageType: .Dropbox)
        let checkSum = try hashing.hash(forURL: fileURL)
        
        guard let result = getIndex(sharingGroupUUID: nil),
            result.sharingGroups.count > 0,
            let sharingGroupUUID = result.sharingGroups[0].sharingGroupUUID else {
            XCTFail()
            return
        }
                                
        let file = ServerAPI.File(fileUUID: fileUUID.uuidString, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID.uuidString, uploadObjectTrackerId: -1, version: .v0(url: fileURL, mimeType: MimeType.text, checkSum: checkSum, changeResolverName: nil, fileGroupUUID: nil, appMetaData: nil))
        
        guard case .success = uploadFile(file: file, uploadIndex: 1, uploadCount: 1) else {
            XCTFail()
            return
        }
        
        guard let sharingGroupUuid = UUID(uuidString: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        guard let indexResult2 = getIndex(sharingGroupUUID: sharingGroupUuid) else {
            XCTFail()
            return
        }
        
        guard let fileIndex = indexResult2.fileIndex,
            fileIndex.count == 1 else {
            XCTFail()
            return
        }

        let fileInfo = fileIndex[0]
        XCTAssert(fileInfo.fileUUID == fileUUID.uuidString)
        XCTAssert(fileInfo.deviceUUID == deviceUUID.uuidString)
        XCTAssert(fileInfo.fileGroupUUID == nil)
        XCTAssert(fileInfo.sharingGroupUUID == sharingGroupUUID)
        XCTAssert(fileInfo.mimeType == MimeType.text.rawValue)
        XCTAssert(fileInfo.sharingGroupUUID == sharingGroupUUID)
        XCTAssert(fileInfo.deleted == false)
        XCTAssert(fileInfo.fileVersion == 0)
        XCTAssert(fileInfo.cloudStorageType == "Dropbox")
        XCTAssert(fileInfo.owningUserId != nil)
    }
    
    func testGetUploadsResultsGivesNilStatusWhenUnknownDeferredIdGiven() throws {
        _ = user.removeUser()
        XCTAssert(user.addUser())
        
        let result = getUploadsResults(deferredUploadId: 0)
        guard case .success(let status) = result else {
            XCTFail()
            return
        }
        
        XCTAssert(status == nil)
    }
}

