//
//  FilesNeedingDownloadTests.swift
//  SyncServerTests
//
//  Created by Christopher G Prince on 9/12/20.
//

import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn
import ChangeResolvers

class FilesNeedingDownloadTests: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, SyncServerTests {
    var deviceUUID: UUID!
    var hashingManager: HashingManager!
    var uploadCompletedHandler: ((Swift.Result<UploadFileResult, Error>) -> ())?
    var downloadCompletedHandler: ((Swift.Result<DownloadFileResult, Error>) -> ())?
    
    var api: ServerAPI!
    var syncServer: SyncServer!
    var uploadQueued: ((SyncServer, _ syncObjectId: UUID) -> ())?
    var uploadStarted: ((SyncServer, _ deferredUploadId:Int64) -> ())?
    var uploadCompleted: ((SyncServer, UploadFileResult) -> ())?
    var error:((SyncServer, Error?) -> ())?
    var syncCompleted:((SyncServer, _ sharingGroupUUID: UUID, _ index: [FileInfo]) -> ())?
    var syncCompletedNoSharingGroup:((SyncServer) -> ())?
    
    var user: TestUser!
    var database: Connection!
    var config:Configuration!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        user = try dropboxUser()
        deviceUUID = UUID()
        database = try Connection(.inMemory)
        hashingManager = HashingManager()
        try hashingManager.add(hashing: user.hashing)
        let serverURL = URL(string: Self.baseURL())!
        config = Configuration(appGroupIdentifier: nil, sqliteDatabasePath: "", serverURL: serverURL, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, configuration: config)
        api = syncServer.api
        uploadQueued = nil
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        
        _ = user.removeUser()
        guard user.addUser() else {
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
    }

    func testFilesNeedingDownloadUnknownSharingGroupFails() {
        do {
            _ = try syncServer.filesNeedingDownload(sharingGroupUUID: UUID())
        } catch {
            return
        }
        XCTFail()
    }
    
    func syncToGetSharingGroupUUID() throws -> UUID {
        let exp = expectation(description: "exp")
        syncCompletedNoSharingGroup = { _ in
            exp.fulfill()
        }
        
        try syncServer.sync()
        waitForExpectations(timeout: 10, handler: nil)
        
        guard syncServer.sharingGroups.count > 0 else {
            throw SyncServerError.internalError("Testing Error")
        }
        
        guard let sharingGroupUUIDString = syncServer.sharingGroups[0].sharingGroupUUID,
            let sharingGroupUUID = UUID(uuidString: sharingGroupUUIDString) else {
            throw SyncServerError.internalError("Testing Error")
        }
        
        return sharingGroupUUID
    }
    
    func sync(withSharingGroupUUID sharingGroupUUID: UUID) throws {
        let exp = expectation(description: "exp")
        syncCompleted = { _, _, _ in
            exp.fulfill()
        }
        
        try syncServer.sync(sharingGroupUUID: sharingGroupUUID)
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testFilesNeedingDownloadKnownSharingGroupWorks() throws {
        let sharingGroupUUID = try syncToGetSharingGroupUUID()
        
        let files = try syncServer.filesNeedingDownload(sharingGroupUUID: sharingGroupUUID)
        XCTAssert(files.count == 0)
    }
    
    func testFilesNeedingDownloadSingleUploadedFileWorks() throws {
        let sharingGroupUUID = try syncToGetSharingGroupUUID()
        
        _ = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID)
        
        let files = try syncServer.filesNeedingDownload(sharingGroupUUID: sharingGroupUUID)
        XCTAssert(files.count == 0)
    }
    
    func testFilesNeedingDownloadSingleFileNeedingDownloadWorks() throws {
        let sharingGroupUUID = try syncToGetSharingGroupUUID()

        let fileUUID1 = UUID()

        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration1])
        
        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable1])

        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        try syncServer.queue(declaration: testObject, uploads: uploadables)
        waitForUploadsToComplete(numberUploads: 1)

        // Reset the database show a state *as if* another client instance had done the upload-- and show the upload as ready for download.
        database = try Connection(.inMemory)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, configuration: config)
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        
        try sync(withSharingGroupUUID:sharingGroupUUID)
        
        let downloadables = try syncServer.filesNeedingDownload(sharingGroupUUID: sharingGroupUUID)
        
        guard downloadables.count == 1 else {
            XCTFail("\(downloadables.count)")
            return
        }
        
        let downloadable = downloadables[0]
        XCTAssert(downloadable.declaration == testObject)
        guard downloadable.downloads.count == 1 else {
            XCTFail()
            return
        }
        
        guard let download = downloadable.downloads.first else {
            XCTFail()
            return
        }
        
        XCTAssert(download.fileVersion == 0)
        XCTAssert(download.uuid == fileUUID1)
    }
    
    func testTwoFilesNeedingDownloadInSameFileGroupWorks() throws {
    }
    
    func testTwoFilesNeedingDownloadInDifferentFileGroupWorks() throws {
    }
}

extension FilesNeedingDownloadTests: SyncServerCredentials {
    func credentialsForServerRequests(_ syncServer: SyncServer) throws -> GenericCredentials {
        return user.credentials
    }
}

extension FilesNeedingDownloadTests: SyncServerDelegate {
    func error(_ syncServer: SyncServer, error: Error?) {
        XCTFail("\(String(describing: error))")
        self.error?(syncServer, error)
    }

    func syncCompleted(_ syncServer: SyncServer) {
        syncCompletedNoSharingGroup?(syncServer)
    }
    
    func syncCompleted(_ syncServer: SyncServer, sharingGroupUUID: UUID, index: [FileInfo]) {
        syncCompleted?(syncServer, sharingGroupUUID, index)
    }
    
    func downloadCompleted(_ syncServer: SyncServer, declObjectId: UUID) {
    }
    
    // A uuid that was initially generated on the client
    func uuidCollision(_ syncServer: SyncServer, type: UUIDCollisionType, from: UUID, to: UUID) {
    }
    
    func uploadQueued(_ syncServer: SyncServer, declObjectId: UUID) {
        self.uploadQueued?(syncServer, declObjectId)
    }
    
    func uploadStarted(_ syncServer: SyncServer, deferredUploadId:Int64) {
        uploadStarted?(syncServer, deferredUploadId)
    }
    
    func uploadCompleted(_ syncServer: SyncServer, result: UploadFileResult) {
        uploadCompleted?(syncServer, result)
    }
    
    func deferredUploadsCompleted(_ syncServer: SyncServer, numberCompleted: Int) {
    }
}
