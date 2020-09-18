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

class ServerAPI_v0Files_Tests: XCTestCase, UserSetup, APITests, ServerAPIDelegator, ServerBasics, TestFiles {
    var hashingManager: HashingManager!
    var uploadCompletedHandler: ((Swift.Result<UploadFileResult, Error>) -> ())?
    var downloadCompletedHandler: ((Swift.Result<DownloadFileResult, Error>) -> ())?
    var api: ServerAPI!
    var deviceUUID: UUID!
    var database: Connection!
    let handlers = DelegateHandlers()
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        uploadCompletedHandler = nil
        handlers.user = try dropboxUser()
        deviceUUID = UUID()
        let database = try Connection(.inMemory)
        try NetworkCache.createTable(db: database)
        let config = Configuration(appGroupIdentifier: nil, sqliteDatabasePath: "", serverURL: URL(string: Self.baseURL())!, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true)
        hashingManager = HashingManager()
        try? hashingManager.add(hashing: DropboxHashing())
        api = ServerAPI(database: database, hashingManager: hashingManager, delegate: self, config: config)
        _ = handlers.user.removeUser()
        XCTAssert(handlers.user.addUser())
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    enum FileUpload {
        case normal
        case appMetaData(AppMetaData)
    }
    
    enum UploadError: Error {
        case getIndex
        case uploadFile
    }
    
    @discardableResult
    func fileUpload(upload: FileUpload = .normal) throws -> ServerAPI.File {
        // Get ready for test.
        let fileUUID = UUID()

        let fileURL = exampleTextFileURL
        
        let checkSum = try hashingManager.hashFor(cloudStorageType: handlers.user.cloudStorageType).hash(forURL: fileURL)
        
        guard let result = getIndex(sharingGroupUUID: nil),
            result.sharingGroups.count > 0,
            let sharingGroupUUID = result.sharingGroups[0].sharingGroupUUID else {
            XCTFail()
            throw UploadError.getIndex
        }
        
        var appMetaData: AppMetaData?
        switch upload {
        case .normal:
            break
        case .appMetaData(let data):
            appMetaData = data
        }
        
        let file = ServerAPI.File(fileUUID: fileUUID.uuidString, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID.uuidString, uploadObjectTrackerId: -1, version: .v0(url: fileURL, mimeType: MimeType.text, checkSum: checkSum, changeResolverName: nil, fileGroup: nil, appMetaData: appMetaData))
        
        guard let uploadResult = uploadFile(file: file, uploadIndex: 1, uploadCount: 1) else {
            XCTFail()
            throw UploadError.uploadFile
        }
        
        switch uploadResult {
        case .success:
            break
        default:
            XCTFail()
        }
        
        return file
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

        let fileURL = exampleTextFileURL
        
        let checkSum = try hashingManager.hashFor(cloudStorageType: handlers.user.cloudStorageType).hash(forURL: fileURL)
        
        guard let result = getIndex(sharingGroupUUID: nil),
            result.sharingGroups.count > 0,
            let sharingGroupUUID = result.sharingGroups[0].sharingGroupUUID else {
            XCTFail()
            return
        }
        
        let fileGroup1 = ServerAPI.File.Version.FileGroup(fileGroupUUID: fileGroupUUID, objectType: "Foo")

        let file1 = ServerAPI.File(fileUUID: fileUUID1.uuidString, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID.uuidString, uploadObjectTrackerId: -1, version: .v0(url: fileURL, mimeType: MimeType.text, checkSum: checkSum, changeResolverName: nil, fileGroup: fileGroup1, appMetaData: nil))
        
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
        
        let fileGroup2 = ServerAPI.File.Version.FileGroup(fileGroupUUID: fileGroupUUID, objectType: "Foo")

        let file2 = ServerAPI.File(fileUUID: fileUUID2.uuidString, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID.uuidString, uploadObjectTrackerId: -1, version: .v0(url: fileURL, mimeType: MimeType.text, checkSum: checkSum, changeResolverName: nil, fileGroup: fileGroup2, appMetaData: nil))
        
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
        let fileURL = exampleTextFileURL
        
        let checkSum = try hashingManager.hashFor(cloudStorageType: handlers.user.cloudStorageType).hash(forURL: fileURL)
        
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
        
        let file = ServerAPI.File(fileUUID: fileUUID.uuidString, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID.uuidString, uploadObjectTrackerId: -1, version: .v0(url: fileURL, mimeType: MimeType.text, checkSum: checkSum, changeResolverName: nil, fileGroup: nil, appMetaData: amd))
        
        guard case .success = uploadFile(file: file, uploadIndex: 1, uploadCount: 1) else {
            XCTFail()
            return nil
        }
        
        let finalFileVersion = downloadFileVersion ?? 0
        
        let download = downloadFile(fileUUID: fileUUID.uuidString, fileVersion: finalFileVersion, downloadObjectTrackerId: -1, sharingGroupUUID: sharingGroupUUID)
        
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
            case .success(let result):
                XCTAssert(!result.contentsChangedOnServer)

                let data1 = try Data(contentsOf: fileURL)
                let data2 = try Data(contentsOf: result.url)
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
        case .success(let result):
            XCTAssert(result.appMetaData == appMetaData)
        default:
            XCTFail()
        }
    }
    
    func testUploadV0FileWithBadInitialChangeResolverDataFails() throws {
        let fileUUID = UUID()
        let fileURL = exampleTextFileURL
        
        let checkSum = try hashingManager.hashFor(cloudStorageType: handlers.user.cloudStorageType).hash(forURL: fileURL)
        
        guard let result = getIndex(sharingGroupUUID: nil),
            result.sharingGroups.count > 0,
            let sharingGroupUUID = result.sharingGroups[0].sharingGroupUUID else {
            XCTFail()
            return
        }
        
        let badChangeResolverName = "foobly"
        
        let file = ServerAPI.File(fileUUID: fileUUID.uuidString, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID.uuidString, uploadObjectTrackerId: -1, version: .v0(url: fileURL, mimeType: MimeType.text, checkSum: checkSum, changeResolverName: badChangeResolverName, fileGroup: nil, appMetaData: nil))
        
        guard case .failure = uploadFile(file: file, uploadIndex: 1, uploadCount: 1) else {
            XCTFail()
            return
        }
    }
    
    func testDeleteV0File() throws {
        let upload = try fileUpload()
        
        let file:ServerAPI.DeletionFile = .fileUUID(upload.fileUUID)
        guard let deletionResult = uploadDeletion(file: file, sharingGroupUUID: upload.sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        switch deletionResult {
        case .fileAlreadyDeleted:
            XCTFail()
        case .fileDeleted(deferredUploadId: let deferredUploadId):
            let status = delayedGetUploadsResults(deferredUploadId: deferredUploadId)
            XCTAssert(status == .completed, "\(String(describing: status))")
        }
    }
}
