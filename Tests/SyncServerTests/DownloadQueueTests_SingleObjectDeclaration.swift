import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn
@testable import TestsCommon

class DownloadQueueTests_SingleObjectDeclaration: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, Delegate, SyncServerTests {
    var deviceUUID: UUID!
    var hashingManager: HashingManager!
    var api: ServerAPI!
    var syncServer: SyncServer!
    var handlers = DelegateHandlers()
    var database: Connection!
    var config:Configuration!
    var fakeHelper:SignInServicesHelperFake!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        handlers = DelegateHandlers()
        
        // Running into `tooManyRequests` HTTP response, so switched from Dropbox to Google for these tests.
        //handlers.user = try googleUser()
        handlers.user = try dropboxUser()
        
        deviceUUID = UUID()
        database = try Connection(.inMemory)
        hashingManager = HashingManager()
        try hashingManager.add(hashing: handlers.user.hashing)
        let serverURL = URL(string: Self.baseURL())!
        config = Configuration(appGroupIdentifier: nil, serverURL: serverURL, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true, deferredCheckInterval: nil)
        fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, requestable: FakeRequestable(), configuration: config, signIns: fakeSignIns, backgroundAsssertable: MainAppBackgroundTask(), migrationRunner: MigrationRunnerFake())
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
        
        let count = try NetworkCache.numberRows(db: database)
        XCTAssert(count == 0, "\(count)")
    }
    
    func runDownload(withFiles: Bool) throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let localFile = Self.exampleTextFileURL
        
        let (uploadableObject, _) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        guard uploadableObject.uploads.count == 1,
            let uploadableFile = uploadableObject.uploads.first else {
            XCTFail()
            return
        }
        
        let downloadable1 = FileToDownload(uuid: uploadableFile.uuid, fileVersion: 0)
        
        var downloadables = [FileToDownload]()
        if withFiles {
            downloadables += [downloadable1]
        }
        
         let downloadObject = ObjectToDownload(fileGroupUUID: uploadableObject.fileGroupUUID, downloads: downloadables)
        
        do {
            try syncServer.queue(download: downloadObject)
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
    
    func testSingleDownloadUsingDownloadHandler() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let localFile = Self.exampleTextFileURL
        
        var uploadable: ObjectUpload!
        var downloadHandlerCalled = false
        
        let (uploadableObject, _) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile) { downloadedObject in
        
            do {
                try self.compare(uploadedFile: localFile, downloadObject: downloadedObject, to: uploadable, downloadHandlerCalled: &downloadHandlerCalled)
            } catch let error {
                XCTFail("\(error)")
            }
        }
        
        uploadable = uploadableObject
        
        guard uploadableObject.uploads.count == 1,
            let uploadableFile = uploadableObject.uploads.first else {
            XCTFail()
            return
        }
        
        let downloadable1 = FileToDownload(uuid: uploadableFile.uuid, fileVersion: 0)
        
        let downloadables = [downloadable1]
        
         let downloadObject = ObjectToDownload(fileGroupUUID: uploadableObject.fileGroupUUID, downloads: downloadables)
        
        try syncServer.queue(download: downloadObject)

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
        
        XCTAssert(downloadHandlerCalled)
    }
    
    func testNonDistinctFileUUIDsInDownloadFilesFails() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let localFile = Self.exampleTextFileURL
        
        let (uploadableObject, _) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        guard uploadableObject.uploads.count == 1,
            let uploadFile = uploadableObject.uploads.first else {
            XCTFail()
            return
        }
        
        let downloadable1 = FileToDownload(uuid: uploadFile.uuid, fileVersion: 0)
        let downloadable2 = FileToDownload(uuid: uploadFile.uuid, fileVersion: 1)

        let downloadables = [downloadable1, downloadable2]
        let downloadObject = ObjectToDownload(fileGroupUUID: uploadableObject.fileGroupUUID, downloads: downloadables)

        do {
            try syncServer.queue(download: downloadObject)
        } catch let error {
            guard let syncServerError = error as? SyncServerError else {
                XCTFail()
                return
            }
            
            XCTAssert(syncServerError == SyncServerError.downloadsDoNotHaveDistinctUUIDs)
            return
        }
        
        XCTFail()
    }
    
    func testFileInDownloadNotInDeclarationFails() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let localFile = Self.exampleTextFileURL
        
        let (uploadableObject, _) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        guard uploadableObject.uploads.count == 1,
            let uploadableFile = uploadableObject.uploads.first else {
            XCTFail()
            return
        }
        
        let downloadable1 = FileToDownload(uuid: uploadableFile.uuid, fileVersion: 0)
        let downloadable2 = FileToDownload(uuid: UUID(), fileVersion: 0)
        let downloadables = [downloadable1, downloadable2]
        let downloadObject = ObjectToDownload(fileGroupUUID: uploadableObject.fileGroupUUID, downloads: downloadables)
        
        do {
            try syncServer.queue(download: downloadObject)
        } catch let error {
            guard let databaseModelError = error as? DatabaseError else {
                XCTFail()
                return
            }
            
            XCTAssert(databaseModelError == DatabaseError.noObject)
            return
        }
        
        XCTFail()
    }
    
    func testDownloadTwoFilesInSameObject() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        let localFile = Self.exampleTextFileURL
        
        // Upload files & create declaration
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let fileDeclaration2 = FileDeclaration(fileLabel: "file2", mimeTypes: [.text], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1, fileDeclaration2])
        try syncServer.register(object: example)

        let fileUpload1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .copy(localFile), uuid: fileUUID1)
        let fileUpload2 = FileUpload(fileLabel: fileDeclaration2.fileLabel, dataSource: .copy(localFile), uuid: fileUUID2)
        
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload1, fileUpload2])

        try syncServer.queue(upload: upload)
        
        waitForUploadsToComplete(numberUploads: 2)
        
        // Download files

        var numberDownloads = 0
        
        let exp1 = expectation(description: "downloadCompleted")
        handlers.extras.downloadCompleted = { _, result in
            numberDownloads += 1

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

            if numberDownloads == 2 {
                exp1.fulfill()
            }
        }

        let downloadable1 = FileToDownload(uuid: fileUUID1, fileVersion: 0)
        let downloadable2 = FileToDownload(uuid: fileUUID2, fileVersion: 0)
        let downloadObject = ObjectToDownload(fileGroupUUID: upload.fileGroupUUID, downloads: [downloadable1, downloadable2])

        try syncServer.queue(download: downloadObject)

        waitForExpectations(timeout: 10, handler: nil)

        let count1 = try DownloadFileTracker.numberRows(db: database)
        XCTAssert(count1 == 0, "\(count1)")

        let count2 = try DownloadObjectTracker.numberRows(db: database)
        XCTAssert(count2 == 0, "\(count2)")
        
        // Second download has been queued, but not downloaded.
    }
    
    func runDownload(withDeletedSharingGroup: Bool) throws {
        let sharingGroupUUID = try getSharingGroup(db: database)
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.jpeg], changeResolverName: nil)

        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let fileUpload1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .copy(exampleTextFileURL), uuid: UUID())
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload1])

        try syncServer.queue(upload: upload)
        waitForUploadsToComplete(numberUploads: 1)
        
        if withDeletedSharingGroup {
            let exp = expectation(description: "exp")
            syncServer.removeFromSharingGroup(sharingGroupUUID: sharingGroupUUID) { error in
                XCTAssertNil(error)
                exp.fulfill()
            }
            waitForExpectations(timeout: 10, handler: nil)
            
            try self.sync()
        }

        let downloadable1 = FileToDownload(uuid: fileUpload1.uuid, fileVersion: 0)
        let downloadObject = ObjectToDownload(fileGroupUUID: upload.fileGroupUUID, downloads: [downloadable1])
        
        do {
            try syncServer.queue(download: downloadObject)
        } catch let error {
            if !withDeletedSharingGroup {
                XCTFail("\(error)")
            }
            return
        }
        
        if withDeletedSharingGroup {
            XCTFail()
            return
        }
        
        waitForDownloadsToComplete(numberExpected: 1)
    }
    
    func testDownloadWithDeletedSharingGroupFails() throws {
        try runDownload(withDeletedSharingGroup: true)
    }
    
    func testDownloadWithNonDeletedSharingGroupWorks() throws {
        try runDownload(withDeletedSharingGroup: false)
    }
    
    // MARK: Prioritization tests
    // See https://github.com/SyncServerII/Neebla/issues/25#issuecomment-898940988
    
    func testDownloadAlreadyDeletedFileFails() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let localFile = Self.exampleTextFileURL
        
        let (uploadableObject, _) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        guard uploadableObject.uploads.count == 1,
            let uploadableFile = uploadableObject.uploads.first else {
            XCTFail()
            return
        }
        
        try delete(object: uploadableObject.fileGroupUUID)
        
        let downloadable1 = FileToDownload(uuid: uploadableFile.uuid, fileVersion: 0)
        let downloadObject = ObjectToDownload(fileGroupUUID: uploadableObject.fileGroupUUID, downloads: [downloadable1])

        do {
            try syncServer.queue(download: downloadObject)
        } catch let error {
            guard let syncServerError = error as? SyncServerError else {
                XCTFail()
                return
            }
            XCTAssert(SyncServerError.attemptToQueueADeletedFile == syncServerError)
            return
        }
        
        XCTFail()
    }
    
    func testDownloadCurrentlyDeletingFileFails() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let localFile = Self.exampleTextFileURL
        
        let (uploadableObject, _) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        guard uploadableObject.uploads.count == 1,
            let uploadableFile = uploadableObject.uploads.first else {
            XCTFail()
            return
        }
                
        // Start the process of deleting the object; Downloads queued after this should fail.
        try syncServer.queue(objectDeletion: uploadableObject.fileGroupUUID)

        let downloadable1 = FileToDownload(uuid: uploadableFile.uuid, fileVersion: 0)
        let downloadObject = ObjectToDownload(fileGroupUUID: uploadableObject.fileGroupUUID, downloads: [downloadable1])

        var failed = false
        do {
            try syncServer.queue(download: downloadObject)
        } catch let error {
            failed = true
            guard let syncServerError = error as? SyncServerError else {
                XCTFail()
                return
            }
            XCTAssert(SyncServerError.attemptToQueueADeletedFile == syncServerError)
        }
        
        guard failed else {
            XCTFail()
            return
        }

        // Wait for deletion to finish.
        let exp = expectation(description: "exp")
        handlers.deletionCompleted = { _, fgUUID in
            XCTAssert(uploadableObject.fileGroupUUID == fgUUID)
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        
        // Wait for some period of time for the deferred deletion to complete.
        Thread.sleep(forTimeInterval: 5)

        let exp2 = expectation(description: "exp2")
        handlers.syncCompleted = { _, _ in
            exp2.fulfill()
        }
        
        // This `sync` is to trigger the check for the deferred upload completion.
        try syncServer.sync()
        
        let exp3 = expectation(description: "exp2")
        handlers.deferredCompleted = { _, operation, fileGroupUUIDs in
            XCTAssert(operation == .deletion)
            XCTAssert(fileGroupUUIDs.count == 1)
            exp3.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testDownloadWhileCurrentlyUploadingIsQueued() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let localFile = Self.exampleTextFileURL
        let objectType: String = "Foo"
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()
        let fileGroupUUID = UUID()
        
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let fileDeclaration2 = FileDeclaration(fileLabel: "file2", mimeTypes: [.text], changeResolverName: nil)

        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1, fileDeclaration2], objectWasDownloaded: nil)
        try syncServer.register(object: example)
                
        let fileUpload1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .copy(localFile), uuid: fileUUID1)
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload1])
        
        try syncServer.queue(upload: upload)
        waitForUploadsToComplete(numberUploads: 1)
        
        // Reset the database to a state *as if* another client instance had done the upload-- and show the upload as ready for download.
        database = try Connection(.inMemory)
        let fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, requestable: FakeRequestable(), configuration: config, signIns: fakeSignIns, backgroundAsssertable: MainAppBackgroundTask(), migrationRunner: MigrationRunnerFake())
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        syncServer.helperDelegate = self
        
        try syncServer.register(object: example)
        
        try sync(withSharingGroupUUID:sharingGroupUUID)
        
        let fileUpload2 = FileUpload(fileLabel: fileDeclaration2.fileLabel, mimeType: .text, dataSource: .copy(localFile), uuid: fileUUID2)
        let upload2 = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload2])
        
        try syncServer.queue(upload: upload2)
        
        let downloadable1 = FileToDownload(uuid: fileUUID1, fileVersion: 0)
        let downloadables = [downloadable1]
        let downloadObject = ObjectToDownload(fileGroupUUID: fileGroupUUID, downloads: downloadables)
        
        // This shouldn't fail-- it should be queued because of the currently active upload.
        try syncServer.queue(download: downloadObject)
        
        // Check to make sure the download isn't active.
        let fileTracker = try DownloadFileTracker.fetchSingleRow(db: database, where: DownloadFileTracker.fileUUIDField.description == fileUUID1)
        guard fileTracker?.status == .notStarted else {
            XCTFail()
            return
        }
        
        waitForUploadsToComplete(numberUploads: 1)
        
        // Trigger the download and wait for it to complete.
        
        let exp1 = expectation(description: "downloadCompleted")
        handlers.extras.downloadCompleted = { _, result in
            switch result.downloadType {
            case .gone:
                XCTFail()
                
            case .success(let url):
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    XCTFail()
                }
            }

            exp1.fulfill()
        }
        
        try syncServer.sync()

        waitForExpectations(timeout: 10, handler: nil)
    }

    func testDownloadWithInactiveUploadIsQueued() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let localFile = Self.exampleTextFileURL
        let objectType: String = "Foo"
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()
        let fileGroupUUID = UUID()
        
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let fileDeclaration2 = FileDeclaration(fileLabel: "file2", mimeTypes: [.text], changeResolverName: nil)

        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1, fileDeclaration2], objectWasDownloaded: nil)
        try syncServer.register(object: example)
                
        let fileUpload1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .copy(localFile), uuid: fileUUID1)
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload1])
        
        try syncServer.queue(upload: upload)
        
        // This is the inactive upload
        let fileUpload2 = FileUpload(fileLabel: fileDeclaration2.fileLabel, mimeType: .text, dataSource: .copy(localFile), uuid: fileUUID2)
        let upload2 = ObjectUpload(objectType: objectType, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload2])
        
        try syncServer.queue(upload: upload2)
        
        waitForUploadsToComplete(numberUploads: 1)
        
        // Make sure the 2nd upload is inactive
        
        let uploadTracker = try UploadFileTracker.fetchSingleRow(db: database, where: UploadFileTracker.fileUUIDField.description == fileUUID2)
        guard uploadTracker?.status == .notStarted else {
            XCTFail()
            return
        }
        
        let downloadable1 = FileToDownload(uuid: fileUUID1, fileVersion: 0)
        let downloadables = [downloadable1]
        let downloadObject = ObjectToDownload(fileGroupUUID: fileGroupUUID, downloads: downloadables)
        
        // This shouldn't fail-- it should be queued because of the currently inactive upload.
        try syncServer.queue(download: downloadObject)
        
        // Check to make sure the download isn't active.
        let fileTracker = try DownloadFileTracker.fetchSingleRow(db: database, where: DownloadFileTracker.fileUUIDField.description == fileUUID1)
        guard fileTracker?.status == .notStarted else {
            XCTFail()
            return
        }
        
        // Trigger the pending upload.
        try syncServer.sync()
        
        waitForUploadsToComplete(numberUploads: 1)
        
        // Trigger the download and wait for it to complete.
        
        let exp1 = expectation(description: "downloadCompleted")
        handlers.extras.downloadCompleted = { _, result in
            switch result.downloadType {
            case .gone:
                XCTFail()
                
            case .success(let url):
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    XCTFail()
                }
            }

            exp1.fulfill()
        }
        
        try syncServer.sync()

        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testDownloadCurrentlyDownloadingFileIsQueued() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let localFile = Self.exampleTextFileURL
        
        let (uploadableObject, _) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        guard uploadableObject.uploads.count == 1,
            let uploadableFile = uploadableObject.uploads.first else {
            XCTFail()
            return
        }
        
        let downloadable1 = FileToDownload(uuid: uploadableFile.uuid, fileVersion: 0)
        let downloadables = [downloadable1]
        let downloadObject = ObjectToDownload(fileGroupUUID: uploadableObject.fileGroupUUID, downloads: downloadables)
        
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
        
        try syncServer.queue(download: downloadObject)
        try syncServer.queue(download: downloadObject)

        waitForExpectations(timeout: 10, handler: nil)
        
        // Don't have sync ready yet. Will just delete the trackers for the second download.
        guard let fileTracker1 = try DownloadFileTracker.fetchSingleRow(db: database, where: DownloadFileTracker.fileUUIDField.description == downloadable1.uuid) else {
            XCTFail()
            return
        }
        try fileTracker1.delete()
        
        guard let fileTracker2 = try DownloadObjectTracker.fetchSingleRow(db: database, where: DownloadObjectTracker.fileGroupUUIDField.description == uploadableObject.fileGroupUUID) else {
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
}
