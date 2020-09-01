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

class ServerAPITests: NetworkingTestCase, APITests, Dropbox {
    let dropboxHasher = DropboxHashing()
    let hashingManager = HashingManager()
    var api:ServerAPI!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        try serverCredentials = createDropboxCredentials()
        try hashingManager.add(hashing: dropboxHasher)
        api = ServerAPI(database: database, hashingManager: hashingManager, delegate: self, config: config)
        try NetworkCache.createTable(db: database)
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
        // Get ready for test.
        removeDropboxUser()
        
        XCTAssert(addDropboxUser())
        
        // Clean up for next test
        XCTAssert(removeDropboxUser())
    }
    
    func testCheckCredsWithAUser() {
        // Get ready for test.
        removeDropboxUser()
        XCTAssert(addDropboxUser())
        
        let result = checkCreds()
        
        switch result {
        case .some(.user):
            break
        default:
            XCTFail()
        }
        
        XCTAssert(removeDropboxUser())
    }
    
    func testCheckCredsWithNoUser() {
        // Get ready for test.
        removeDropboxUser()
        
        let result = checkCreds()
        
        switch result {
        case .some(.noUser):
            break
        default:
            XCTFail()
        }
    }
    
    func testIndexWithNoContentsExpectation() {
        // Get ready for test.
        removeDropboxUser()
        XCTAssert(addDropboxUser())
        
        guard let result = getIndex(sharingGroupUUID: nil) else {
            XCTFail()
            return
        }
        
        XCTAssert(result.fileIndex == nil)
        XCTAssert(result.sharingGroups.count == 1)
        XCTAssert(removeDropboxUser())
    }
    
    func testIndexWithFile() throws {
        // Get ready for test.
        removeDropboxUser()
        XCTAssert(addDropboxUser())
        
        let fileUUID = UUID()

        let thisDirectory = TestingFile.directoryOfFile(#file)
        let fileURL = thisDirectory.appendingPathComponent(exampleTextFile)
        
        let hashing = try hashingManager.hashFor(cloudStorageType: .Dropbox)
        let checkSum = try hashing.hash(forURL: fileURL)
        
        guard let result = getIndex(sharingGroupUUID: nil),
            result.sharingGroups.count > 0,
            let sharingGroupUUID = result.sharingGroups[0].sharingGroupUUID else {
            XCTFail()
            return
        }
        
        let file = ServerAPI.File(fileUUID: fileUUID.uuidString, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID.uuidString, version: .v0(source: .url(fileURL), mimeType: MimeType.text, checkSum: checkSum, changeResolverName: nil, fileGroupUUID: nil, appMetaData: nil))
        
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
                
        XCTAssert(removeDropboxUser())
    }
    
    func testGetUploadsResultsGivesNilStatusWhenUnknownDeferredIdGiven() throws {
        // Get ready for test.
        removeDropboxUser()
        XCTAssert(addDropboxUser())
        
        let result = getUploadsResults(deferredUploadId: 0)
        guard case .success(let status) = result else {
            XCTFail()
            return
        }
        
        XCTAssert(status == nil)
        
        XCTAssert(removeDropboxUser())
    }
}
