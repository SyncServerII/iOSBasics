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
    let hashingManager = HashingManager()
    let dropboxHashing = DropboxHashing()
    let config = Networking.Configuration(temporaryFileDirectory: Files.getDocumentsDirectory(), temporaryFilePrefix: "SyncServer", temporaryFileExtension: "dat", baseURL: baseURL(), minimumServerVersion: nil, packageTests: true)
    var uploadCompletedHandler: ((_ result: Swift.Result<UploadFileResult, Error>) -> ())?
    var downloadCompletedHandler: ((_ result: Swift.Result<DownloadFileResult, Error>) -> ())?
    
    override func setUpWithError() throws {
        database = try Connection(.inMemory)
        try hashingManager.add(hashing: dropboxHashing)
        credentials = try setupDropboxCredentials()
        api = ServerAPI(database: database, hashingManager: hashingManager, delegate: self, config: config)
        uploadCompletedHandler = nil
        try NetworkCache.createTable(db: database)
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    enum FileUpload {
        case normal
        case appMetaData(AppMetaData)
    }
    
    func fileUpload(upload: FileUpload = .normal) throws {
        // Get ready for test.
        removeDropboxUser()
        XCTAssert(addDropboxUser())
        
        let fileUUID = UUID()

        let thisDirectory = TestingFile.directoryOfFile(#file)
        let fileURL = thisDirectory.appendingPathComponent(exampleTextFile)
        
        let checkSum = try dropboxHashing.hash(forURL: fileURL)
        
        guard let result = getIndex(sharingGroupUUID: nil),
            result.sharingGroups.count > 0,
            let masterVersion = result.sharingGroups[0].masterVersion,
            let sharingGroupUUID = result.sharingGroups[0].sharingGroupUUID else {
            XCTFail()
            return
        }
        
        var appMetaData: AppMetaData?
        switch upload {
        case .normal:
            break
        case .appMetaData(let data):
            appMetaData = data
        }
        
        let file = ServerAPI.File(localURL: fileURL, fileUUID: fileUUID.uuidString, fileGroupUUID: nil, sharingGroupUUID: sharingGroupUUID, mimeType: MimeType.text, deviceUUID: deviceUUID.uuidString, appMetaData: appMetaData, fileVersion: 0, checkSum: checkSum)
        
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
    
    func testFileUpload() throws {
        try fileUpload()
    }
    
    func testFileUploadWithAppMetaData() throws {
        let appMetaData = AppMetaData(version: 0, contents: "foobly")
        try fileUpload(upload: .appMetaData(appMetaData))
    }
    
    func testFileUploadWithCommit() throws {
        // Get ready for test.
        removeDropboxUser()
        XCTAssert(addDropboxUser())
        
        let fileUUID = UUID()

        let thisDirectory = TestingFile.directoryOfFile(#file)
        let fileURL = thisDirectory.appendingPathComponent(exampleTextFile)
        
        let checkSum = try dropboxHashing.hash(forURL: fileURL)
        
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
    
    // The parameters are set only for failure testing.
    func downloadFile(downloadFileVersion:FileVersionInt? = nil,
        downloadMasterVersion: MasterVersionInt? = nil,
        expectedFailure: Bool = false) throws {
        
        // Get ready for test.
        removeDropboxUser()
        XCTAssert(addDropboxUser())
        
        let fileUUID = UUID()

        let thisDirectory = TestingFile.directoryOfFile(#file)
        let fileURL = thisDirectory.appendingPathComponent(exampleTextFile)
        
        let checkSum = try dropboxHashing.hash(forURL: fileURL)
        
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
        
        let finalFileVersion = downloadFileVersion ?? fileVersion
        let finalMasterVersion = downloadMasterVersion ?? masterVersion + 1
        
        let download = downloadFile(fileUUID: fileUUID.uuidString, fileVersion: finalFileVersion, serverMasterVersion: finalMasterVersion, sharingGroupUUID: sharingGroupUUID, appMetaDataVersion: nil)
        
        if expectedFailure {
            if let _ = downloadMasterVersion {
                guard case .success(let downloadResult) = download else {
                    XCTFail()
                    return
                }
                
                switch downloadResult {
                case .serverMasterVersionUpdate:
                    break
                    
                default:
                    XCTFail()
                }
            }
            else {
                guard case .failure = download else {
                    XCTFail()
                    return
                }
            }
        }
        else {
            guard case .success(let downloadResult) = download else {
                XCTFail()
                return
            }
            
            switch downloadResult {
            case .success(url: let url, appMetaData: let appMetaData, checkSum: let checkSumDownloaded, cloudStorageType: let cloudStorageType, contentsChangedOnServer: let changed):
            
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
        }
        
        XCTAssert(removeDropboxUser())
    }
    
    func testDownloadFile() throws {
        try downloadFile()
    }
    
    func testDownloadFileFailsWithBadFileVersion() throws {
        try downloadFile(downloadFileVersion: 1, expectedFailure: true)
    }
    
    func testDownloadFileFailsWithBadMasterVersion() throws {
        try downloadFile(downloadMasterVersion: 0, expectedFailure: true)
    }
}
