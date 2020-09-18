import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn

class DownloadQueueTests_SingleObjectDeclaration: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, Delegate, SyncServerTests {
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
    
    func runDownload(withFiles: Bool) throws {
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let localFile = Self.exampleTextFileURL
        
        let declaration = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        guard declaration.declaredFiles.count == 1,
            let declaredFile = declaration.declaredFiles.first else {
            XCTFail()
            return
        }
        
        let downloadable1 = FileDownload(uuid: declaredFile.uuid, fileVersion: 0)
        
        var downloadables = Set<FileDownload>()
        if withFiles {
            downloadables.insert(downloadable1)
        }
        
        do {
            try syncServer.queue(downloads: downloadables, declaration: declaration)
        } catch let error {
            if withFiles {
                XCTFail("\(error)")
            }
            return
        }
        
        if !withFiles {
            XCTFail()
            return
        }

        let exp = expectation(description: "exp")
        handlers.downloadQueue = { _, result in
            switch result {
            case .completed(let result):
            switch result.downloadType {
                case .gone:
                    XCTFail()
                    
                case .success(let url):
                    do {
                        let data1 = try Data(contentsOf: localFile)
                        let data2 = try Data(contentsOf: url)
                        XCTAssert(data1 == data2)
                        try FileManager.default.removeItem(at: url)
                    } catch {
                        XCTFail()
                    }
                }
            case .queued:
                XCTFail()
            }

            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        
        XCTAssert(try DownloadFileTracker.numberRows(db: database) == 0)
        XCTAssert(try DownloadObjectTracker.numberRows(db: database) == 0)
    }
    
    func testNoDeclaredFilesFails() throws {
        try runDownload(withFiles: false)
    }
    
    func testDeclaredFileWorks() throws {
        try runDownload(withFiles: true)
    }
    
    #warning("Need to write these tests")

    func testNotDistinctFileUUIDsInDeclaration() {
    }
    
    func testNotDistinctFileUUIDsInDownloadFiles() {
    }
    
    func testSomeFilesInDownloadNotInDeclarationFails() {
    }
    
    func testUndeclaredObjectFails() {
    }
    
    func testDeclaredObjectDoesNotMatchThatUsedFails() {
    }
    
    func testDownloadCurrentlyDownloadingFileFails() {
    }
    
    func testDownloadTwoFilesInSameObjects() {
    }
    
    func testQueueDownloadsFromDifferentObject() {
    }
}
