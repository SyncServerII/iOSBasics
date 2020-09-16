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

class FilesNeedingDownloadTests: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, SyncServerTests, Delegate {
    var deviceUUID: UUID!
    var hashingManager: HashingManager!
    var uploadCompletedHandler: ((Swift.Result<UploadFileResult, Error>) -> ())?
    var downloadCompletedHandler: ((Swift.Result<DownloadFileResult, Error>) -> ())?
    
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
        handlers.syncCompleted = { _, result in
            guard case .noIndex = result else {
                XCTFail()
                exp.fulfill()
                return
            }
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
        
        try syncServer.queue(uploads: uploadables, declaration: testObject)
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
        let sharingGroupUUID = try syncToGetSharingGroupUUID()

        let fileUUID1 = UUID()
        let fileUUID2 = UUID()

        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declaration2 = FileDeclaration(uuid: fileUUID2, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)

        let declarations = Set<FileDeclaration>([declaration1, declaration2])
        
        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleTextFileURL))
        let uploadable2 = FileUpload(uuid: fileUUID2, dataSource: .copy(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable1, uploadable2])

        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        try syncServer.queue(uploads: uploadables, declaration: testObject)
        waitForUploadsToComplete(numberUploads: 2)
        
        // Reset the database to a state *as if* another client instance had done the upload-- and show the upload as ready for download.
        database = try Connection(.inMemory)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, configuration: config)
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        
        try sync(withSharingGroupUUID:sharingGroupUUID)
        
        let downloadables = try syncServer.filesNeedingDownload(sharingGroupUUID: sharingGroupUUID)
        
        // Single declared *object*
        guard downloadables.count == 1 else {
            XCTFail("\(downloadables.count)")
            return
        }
        
        let downloadable = downloadables[0]
        XCTAssert(downloadable.declaration == testObject)
        
        // Two files needing download within that object declaration.
        guard downloadable.downloads.count == 2 else {
            XCTFail()
            return
        }

        let file1 = downloadable.downloads.filter {$0.uuid == fileUUID1 && $0.fileVersion == 0}
        XCTAssert(file1.count == 1)
        
        let file2 = downloadable.downloads.filter {$0.uuid == fileUUID2 && $0.fileVersion == 0}
        XCTAssert(file2.count == 1)
    }
    
    func testTwoFilesNeedingDownloadInDifferentFileGroupWorks() throws {
        let sharingGroupUUID = try syncToGetSharingGroupUUID()

        let fileGroupUUID1 = UUID()
        let fileGroupUUID2 = UUID()

        func queue(fileGroupUUID: UUID) throws -> UUID {
            let fileUUID1 = UUID()

            let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)

            let declarations = Set<FileDeclaration>([declaration1])
            
            let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleTextFileURL))
            let uploadables = Set<FileUpload>([uploadable1])

            let testObject = ObjectDeclaration(fileGroupUUID: fileGroupUUID, objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
            
            try syncServer.queue(uploads: uploadables, declaration: testObject)
            waitForUploadsToComplete(numberUploads: 1)
            
            return fileUUID1
        }
        
        let fileUUID1 = try queue(fileGroupUUID: fileGroupUUID1)
        let fileUUID2 = try queue(fileGroupUUID: fileGroupUUID2)

        // Reset the database to a state *as if* another client instance had done the upload-- and show the upload as ready for download.
        database = try Connection(.inMemory)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, configuration: config)
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        
        try sync(withSharingGroupUUID:sharingGroupUUID)
        
        let downloadables = try syncServer.filesNeedingDownload(sharingGroupUUID: sharingGroupUUID)
        
        guard downloadables.count == 2 else {
            XCTFail()
            return
        }
        
        let results1 = downloadables.filter {$0.declaration.fileGroupUUID == fileGroupUUID1}
        guard results1.count == 1 else {
            XCTFail()
            return
        }
        
        let file1 = results1[0].downloads.filter {$0.uuid == fileUUID1 && $0.fileVersion == 0}
        XCTAssert(file1.count == 1)
        
        let results2 = downloadables.filter {$0.declaration.fileGroupUUID == fileGroupUUID2}
        guard results2.count == 1 else {
            XCTFail()
            return
        }

        let file2 = results2[0].downloads.filter {$0.uuid == fileUUID2 && $0.fileVersion == 0}
        XCTAssert(file2.count == 1)
    }
}
