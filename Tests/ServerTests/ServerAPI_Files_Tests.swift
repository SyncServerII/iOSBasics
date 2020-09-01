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

class ServerAPI_v0Files_Tests: APITestCase, APITests {
    override func setUpWithError() throws {
        try super.setUpWithError()
        user = try dropboxUser()
        uploadCompletedHandler = nil
        try NetworkCache.createTable(db: database)
        _ = user.removeUser()
        XCTAssert(user.addUser())
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
        let fileUUID = UUID()

        let thisDirectory = TestingFile.directoryOfFile(#file)
        let fileURL = thisDirectory.appendingPathComponent(exampleTextFile)
        let checkSum = try hashingManager.hashFor(cloudStorageType: user.cloudStorageType).hash(forURL: fileURL)
        
        guard let result = getIndex(sharingGroupUUID: nil),
            result.sharingGroups.count > 0,
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
        
        let file = ServerAPI.File(fileUUID: fileUUID.uuidString, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID.uuidString, version: .v0(source: .url(fileURL), mimeType: MimeType.text, checkSum: checkSum, changeResolverName: nil, fileGroupUUID: nil, appMetaData: appMetaData))
        
        guard let uploadResult = uploadFile(file: file, uploadIndex: 1, uploadCount: 1) else {
            XCTFail()
            return
        }
        
        switch uploadResult {
        case .success:
            break
        default:
            XCTFail()
        }
    }
    
    func testFileUpload() throws {
        try fileUpload()
    }
    
    func testFileUploadWithAppMetaData() throws {
        let appMetaData = AppMetaData(contents: "foobly")
        try fileUpload(upload: .appMetaData(appMetaData))
    }
    
    func testFileTwoUploadsInBatchWorks() throws {
        // Get ready for test.
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()
        let fileGroupUUID = UUID()

        let thisDirectory = TestingFile.directoryOfFile(#file)
        let fileURL = thisDirectory.appendingPathComponent(exampleTextFile)
        
        let checkSum = try hashingManager.hashFor(cloudStorageType: user.cloudStorageType).hash(forURL: fileURL)
        
        guard let result = getIndex(sharingGroupUUID: nil),
            result.sharingGroups.count > 0,
            let sharingGroupUUID = result.sharingGroups[0].sharingGroupUUID else {
            XCTFail()
            return
        }
        
        let file1 = ServerAPI.File(fileUUID: fileUUID1.uuidString, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID.uuidString, version: .v0(source: .url(fileURL), mimeType: MimeType.text, checkSum: checkSum, changeResolverName: nil, fileGroupUUID: fileGroupUUID.uuidString, appMetaData: nil))
        
        guard let uploadResult1 = uploadFile(file: file1, uploadIndex: 1, uploadCount: 2) else {
            XCTFail()
            return
        }
        
        switch uploadResult1 {
        case .success:
            break
        default:
            XCTFail()
        }
        
        let file2 = ServerAPI.File(fileUUID: fileUUID2.uuidString, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID.uuidString, version: .v0(source: .url(fileURL), mimeType: MimeType.text, checkSum: checkSum, changeResolverName: nil, fileGroupUUID: fileGroupUUID.uuidString, appMetaData: nil))
        
        guard let uploadResult2 = uploadFile(file: file2, uploadIndex: 2, uploadCount: 2) else {
            XCTFail()
            return
        }
        
        switch uploadResult2 {
        case .success:
            break
        default:
            XCTFail("\(uploadResult2)")
        }
    }
    
    @discardableResult
    func downloadFile(downloadFileVersion:FileVersionInt? = nil,
        expectedFailure: Bool = false, appMetaData: String? = nil) throws -> DownloadFileResult? {
        
        var returnResult: DownloadFileResult?
        
        let fileUUID = UUID()

        let thisDirectory = TestingFile.directoryOfFile(#file)
        let fileURL = thisDirectory.appendingPathComponent(exampleTextFile)
        
        let checkSum = try hashingManager.hashFor(cloudStorageType: user.cloudStorageType).hash(forURL: fileURL)
        
        guard let result = getIndex(sharingGroupUUID: nil),
            result.sharingGroups.count > 0,
            let sharingGroupUUID = result.sharingGroups[0].sharingGroupUUID else {
            XCTFail()
            return nil
        }
        
        var amd: AppMetaData?
        if let appMetaData = appMetaData {
            amd = AppMetaData(contents: appMetaData)
        }
        
        let file = ServerAPI.File(fileUUID: fileUUID.uuidString, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID.uuidString, version: .v0(source: .url(fileURL), mimeType: MimeType.text, checkSum: checkSum, changeResolverName: nil, fileGroupUUID: nil, appMetaData: amd))
        
        guard case .success = uploadFile(file: file, uploadIndex: 1, uploadCount: 1) else {
            XCTFail()
            return nil
        }
        
        let finalFileVersion = downloadFileVersion ?? 0
        
        let download = downloadFile(fileUUID: fileUUID.uuidString, fileVersion: finalFileVersion, sharingGroupUUID: sharingGroupUUID)
        
        if expectedFailure {
            guard case .failure = download else {
                XCTFail()
                return nil
            }
        }
        else {
            guard case .success(let downloadResult) = download else {
                XCTFail()
                return nil
            }
            
            returnResult = downloadResult
            
            switch downloadResult {
            case .success(url: let url, appMetaData: _, checkSum: let checkSumDownloaded, cloudStorageType: let cloudStorageType, contentsChangedOnServer: let changed):
            
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
        
        return returnResult
    }
    
    func testDownloadFile() throws {
        try downloadFile()
    }
    
    func testDownloadFileFailsWithBadFileVersion() throws {
        try downloadFile(downloadFileVersion: 1, expectedFailure: true)
    }
    
    func testDownloadFileWithAppMetaData() throws {
        let appMetaData = "foobly"
        guard let result = try downloadFile(appMetaData: appMetaData) else {
            XCTFail()
            return
        }
        
        switch result {
        case .success(url: _, appMetaData: let amd, checkSum: _, cloudStorageType: _, contentsChangedOnServer: _):
            XCTAssert(appMetaData == amd?.contents)
        default:
            XCTFail()
        }
    }
    
    func testUploadV0FileWithBadInitialChangeResolverDataFails() throws {
        let fileUUID = UUID()

        let thisDirectory = TestingFile.directoryOfFile(#file)
        let fileURL = thisDirectory.appendingPathComponent(exampleTextFile)
        
        let checkSum = try hashingManager.hashFor(cloudStorageType: user.cloudStorageType).hash(forURL: fileURL)
        
        guard let result = getIndex(sharingGroupUUID: nil),
            result.sharingGroups.count > 0,
            let sharingGroupUUID = result.sharingGroups[0].sharingGroupUUID else {
            XCTFail()
            return
        }
        
        let badChangeResolverName = "foobly"
        
        let file = ServerAPI.File(fileUUID: fileUUID.uuidString, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID.uuidString, version: .v0(source: .url(fileURL), mimeType: MimeType.text, checkSum: checkSum, changeResolverName: badChangeResolverName, fileGroupUUID: nil, appMetaData: nil))
        
        guard case .failure = uploadFile(file: file, uploadIndex: 1, uploadCount: 1) else {
            XCTFail()
            return
        }
    }
}
