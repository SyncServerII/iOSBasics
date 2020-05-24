//
//  ServerAPI_Files_Tests.swift
//  iOSBasicsTests
//
//  Created by Christopher G Prince on 5/20/20.
//

import XCTest
@testable import iOSBasics
import iOSSignIn
import ServerShared
import iOSShared
import iOSDropbox
import SQLite

class ServerAPI_Files_Tests: XCTestCase, APITests, Dropbox, ServerBasics {
    var credentials: GenericCredentials!
    var api:ServerAPI!
    let deviceUUID = UUID()
    var database: Connection!
    let hashing:CloudStorageHashing = DropboxHashing()
    let config = Networking.Configuration(temporaryFileDirectory: Files.getDocumentsDirectory(), temporaryFilePrefix: "SyncServer", temporaryFileExtension: "dat", baseURL: baseURL(), minimumServerVersion: nil, packageTests: true)
    var uploadCompletedHandler: ((_ result: Swift.Result<UploadFileResult, Error>) -> ())?
    
    override func setUpWithError() throws {
        database = try Connection(.inMemory)
        credentials = try setupDropboxCredentials()
        api = ServerAPI(database: database, delegate: self, config: config)
        uploadCompletedHandler = nil
        try NetworkCache.createTable(db: database)
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testFileUpload() throws {
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
        
        guard let uploadResult = uploadFile(file: file, masterVersion: masterVersion) else {
            XCTFail()
            return
        }
        
        switch uploadResult {
        case .success:
            break
        default:
            XCTFail()
        }
        
        XCTAssert(removeDropboxUser())
    }
    
    func testFileUploadWithCommit() throws {
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
        
        guard let uuid = UUID(uuidString: sharingGroupUUID) else {
            XCTFail()
            return
        }

        guard case .success = commitUploads(masterVersion: masterVersion, sharingGroupUUID: uuid) else {
            XCTFail()
            return
        }
        
        XCTAssert(removeDropboxUser())
    }
    
    func testDownloadFile() throws {
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
        
        let fileVersion:FileVersionInt = 0
        
        let file = ServerAPI.File(localURL: fileURL, fileUUID: fileUUID.uuidString, fileGroupUUID: nil, sharingGroupUUID: sharingGroupUUID, mimeType: MimeType.text, deviceUUID: deviceUUID.uuidString, appMetaData: nil, fileVersion: fileVersion, checkSum: checkSum)
        
        guard case .success = uploadFile(file: file, masterVersion: masterVersion) else {
            XCTFail()
            return
        }
        
        guard let uuid = UUID(uuidString: sharingGroupUUID) else {
            XCTFail()
            return
        }

        guard case .success = commitUploads(masterVersion: masterVersion, sharingGroupUUID: uuid) else {
            XCTFail()
            return
        }
        
        guard case .success(let downloadedFile) = downloadFile(fileUUID: fileUUID.uuidString, fileVersion: fileVersion, serverMasterVersion: masterVersion + 1, sharingGroupUUID: sharingGroupUUID, appMetaDataVersion: nil) else {
            XCTFail()
            return
        }
        
        switch downloadedFile {
        case .content(url: let url, appMetaData: let appMetaData, checkSum: let checkSumDownloaded, cloudStorageType: let cloudStorageType, contentsChangedOnServer: let changed):
        
            XCTAssert(appMetaData == nil)
            XCTAssert(!changed)
            XCTAssert(cloudStorageType == .Dropbox)
            XCTAssert(checkSum == checkSumDownloaded)
            
            let data1 = try Data(contentsOf: fileURL)
            let data2 = try Data(contentsOf: url)
            XCTAssert(data1 == data2)
            
        default:
            XCTFail()
        }

        XCTAssert(removeDropboxUser())
    }
}
