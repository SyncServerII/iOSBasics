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
        handlers.extras.downloadCompleted = { _, result in
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
    
    func testNonDistinctFileUUIDsInDeclarationFails() throws {
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let localFile = Self.exampleTextFileURL
        
        let declaration = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        guard declaration.declaredFiles.count == 1,
            let declaredFile = declaration.declaredFiles.first else {
            XCTFail()
            return
        }
        
        let downloadable1 = FileDownload(uuid: declaredFile.uuid, fileVersion: 0)
        
        let downloadables = Set<FileDownload>([downloadable1])
        
        var declaredFiles = declaration.declaredFiles
        let newDeclaredFile = FileDeclaration(uuid: declaredFile.uuid, mimeType: declaredFile.mimeType, cloudStorageType: declaredFile.cloudStorageType, appMetaData: UUID().uuidString, changeResolverName: nil)
        declaredFiles.insert(newDeclaredFile)

        let newDeclaration = ObjectDeclaration(fileGroupUUID: declaration.fileGroupUUID, objectType: declaration.objectType, sharingGroupUUID: declaration.sharingGroupUUID, declaredFiles: declaredFiles)
        
        do {
            try syncServer.queue(downloads: downloadables, declaration: newDeclaration)
        } catch let error {
            guard let syncServerError = error as? SyncServerError else {
                XCTFail()
                return
            }
            
            XCTAssert(syncServerError == SyncServerError.declaredFilesDoNotHaveDistinctUUIDs)
        }
    }
    
    func testNonDistinctFileUUIDsInDownloadFilesFails() throws {
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let localFile = Self.exampleTextFileURL
        
        let declaration = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        guard declaration.declaredFiles.count == 1,
            let declaredFile = declaration.declaredFiles.first else {
            XCTFail()
            return
        }
        
        let downloadable1 = FileDownload(uuid: declaredFile.uuid, fileVersion: 0)
        let downloadable2 = FileDownload(uuid: declaredFile.uuid, fileVersion: 1)

        let downloadables = Set<FileDownload>([downloadable1, downloadable2])
        
        do {
            try syncServer.queue(downloads: downloadables, declaration: declaration)
        } catch let error {
            guard let syncServerError = error as? SyncServerError else {
                XCTFail()
                return
            }
            
            XCTAssert(syncServerError == SyncServerError.downloadsDoNotHaveDistinctUUIDs)
        }
    }
    
    func testFileInDownloadNotInDeclarationFails() throws {
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let localFile = Self.exampleTextFileURL
        
        let declaration = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        guard declaration.declaredFiles.count == 1,
            let declaredFile = declaration.declaredFiles.first else {
            XCTFail()
            return
        }
        
        let downloadable1 = FileDownload(uuid: declaredFile.uuid, fileVersion: 0)
        let downloadable2 = FileDownload(uuid: UUID(), fileVersion: 0)

        let downloadables = Set<FileDownload>([downloadable1, downloadable2])
        
        do {
            try syncServer.queue(downloads: downloadables, declaration: declaration)
        } catch let error {
            guard let syncServerError = error as? SyncServerError else {
                XCTFail()
                return
            }
            
            XCTAssert(syncServerError == SyncServerError.fileNotDeclared)
        }
    }
    
    func testUndeclaredObjectFails() throws {
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let localFile = Self.exampleTextFileURL
        
        let _ = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        
        let fileUUID1 = UUID()
        let declaration2 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations2 = Set<FileDeclaration>([declaration2])

        let object2 = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations2)
        
        let downloadable1 = FileDownload(uuid: fileUUID1, fileVersion: 0)
        let downloadables = Set<FileDownload>([downloadable1])
        
        do {
            try syncServer.queue(downloads: downloadables, declaration: object2)
        } catch let error {
            guard let syncServerError = error as? SyncServerError else {
                XCTFail()
                return
            }
            
            XCTAssert(syncServerError == SyncServerError.noObject)
        }
    }
        
    func testDownloadCurrentlyDownloadingFileIsQueued() throws {
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let localFile = Self.exampleTextFileURL
        
        let declaration = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        guard declaration.declaredFiles.count == 1,
            let declaredFile = declaration.declaredFiles.first else {
            XCTFail()
            return
        }
        
        let downloadable1 = FileDownload(uuid: declaredFile.uuid, fileVersion: 0)
        let downloadables = Set<FileDownload>([downloadable1])
        
        let exp1 = expectation(description: "downloadCompleted")
        handlers.extras.downloadCompleted = { _, result in
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

            exp1.fulfill()
        }
        
        let exp2 = expectation(description: "downloadQueued")
        handlers.extras.downloadQueued = { _ in
            exp2.fulfill()
        }
        
        try syncServer.queue(downloads: downloadables, declaration: declaration)
        try syncServer.queue(downloads: downloadables, declaration: declaration)

        waitForExpectations(timeout: 10, handler: nil)
        
        // Don't have sync ready yet. Will just delete the trackers for the second download.
        guard let fileTracker1 = try DownloadFileTracker.fetchSingleRow(db: database, where: DownloadFileTracker.fileUUIDField.description == downloadable1.uuid) else {
            XCTFail()
            return
        }
        try fileTracker1.delete()
        
        guard let fileTracker2 = try DownloadObjectTracker.fetchSingleRow(db: database, where: DownloadObjectTracker.fileGroupUUIDField.description == declaration.fileGroupUUID) else {
            XCTFail()
            return
        }
        try fileTracker2.delete()
        
        let count1 = try DownloadFileTracker.numberRows(db: database)
        XCTAssert(count1 == 0, "\(count1)")
        
        let count2 = try DownloadObjectTracker.numberRows(db: database)
        XCTAssert(count2 == 0, "\(count2)")
        
        // Second download has been queued, but not downloaded.
    }
    
    #warning("Need to write these tests")
    
    func testDownloadTwoFilesInSameObjects() {
    }
    
    func testQueueDownloadsFromDifferentObject() {
    }
}
