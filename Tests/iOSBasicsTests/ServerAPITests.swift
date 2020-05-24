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

class ServerAPITests: XCTestCase, APITests, ServerBasics, Dropbox {
    var credentials: GenericCredentials!
    var api:ServerAPI!
    let hashing: CloudStorageHashing = DropboxHashing()
    let deviceUUID = UUID()
    var database: Connection!
    let config = Networking.Configuration(temporaryFileDirectory: Files.getDocumentsDirectory(), temporaryFilePrefix: "SyncServer", temporaryFileExtension: "dat", baseURL: baseURL(), minimumServerVersion: nil, packageTests: true)
    var uploadCompletedHandler: ((_ result: Swift.Result<UploadFileResult, Error>) -> ())?

    
    override func setUpWithError() throws {
        database = try Connection(.inMemory)
        credentials = try setupDropboxCredentials()
        api = ServerAPI(database: database, delegate: self, config: config)
        try NetworkCache.createTable(db: database)
    }

    override func tearDownWithError() throws {
    }

    func testHealthCheck() throws {
        let exp = expectation(description: "exp")

        api.healthCheck { response, error  in
            XCTAssert(response?.currentServerDateTime != nil)
            XCTAssert(error == nil)
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
        
        let checkSum = try hashing.hash(forURL: fileURL)
        
        guard let result = getIndex(sharingGroupUUID: nil),
            result.sharingGroups.count > 0,
            let masterVersion = result.sharingGroups[0].masterVersion,
            let sharingGroupUUID = result.sharingGroups[0].sharingGroupUUID else {
            XCTFail()
            return
        }
        
        let file = ServerAPI.File(localURL: fileURL, fileUUID: fileUUID.uuidString, fileGroupUUID: nil, sharingGroupUUID: sharingGroupUUID, mimeType: MimeType.text, deviceUUID: deviceUUID.uuidString, appMetaData: nil, fileVersion: 0, checkSum: checkSum)
        
        guard case .success = uploadFile(file: file, masterVersion: masterVersion) else {
            XCTFail()
            return
        }
        
        guard let sharingGroupUuid = UUID(uuidString: sharingGroupUUID) else {
            XCTFail()
            return
        }

        guard case .success = commitUploads(masterVersion: masterVersion, sharingGroupUUID: sharingGroupUuid) else {
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
        XCTAssert(fileInfo.appMetaDataVersion == nil)
        XCTAssert(fileInfo.fileVersion == 0)
        XCTAssert(fileInfo.cloudStorageType == "Dropbox")
        XCTAssert(fileInfo.owningUserId != nil)
                
        XCTAssert(removeDropboxUser())
    }
}

