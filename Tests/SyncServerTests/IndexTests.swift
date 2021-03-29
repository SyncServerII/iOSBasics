//
//  IndexTests.swift
//  SyncServerTests
//
//  Created by Christopher G Prince on 9/11/20.
//

import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn
import ChangeResolvers
@testable import TestsCommon

class IndexTests: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, Delegate, SyncServerTests {
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
        handlers.user = try dropboxUser()
        deviceUUID = UUID()
        database = try Connection(.inMemory)
        hashingManager = HashingManager()
        try hashingManager.add(hashing: handlers.user.hashing)
        let serverURL = URL(string: Self.baseURL())!
        config = Configuration(appGroupIdentifier: nil, serverURL: serverURL, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true, deferredCheckInterval: nil)
        fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, requestable: FakeRequestable(), configuration: config, signIns: fakeSignIns, backgroundAsssertable: MainAppBackgroundTask())
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
        
        syncServer.helperDelegate = self
        handlers.objectType = { _, _ in
            return nil
        }
    }

    override func tearDownWithError() throws {
        // All temporary files should have been removed prior to end of test.
        let filePaths = try FileManager.default.contentsOfDirectory(atPath: config.temporaryFiles.directory.path)
        XCTAssert(filePaths.count == 0, "\(filePaths.count)")
    }

    func testIndexCalledDirectly() throws {
        let sharingGroupUUID = try getSharingGroupUUID()

        let exp = expectation(description: "exp")
        
        handlers.syncCompleted = { _, result in
            guard case .index(let uuid, let index) = result else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            XCTAssert(sharingGroupUUID == uuid)
            XCTAssert(index.count == 0)
            guard let result = try? SharingEntry.fetchSingleRow(db: self.database, where: SharingEntry.sharingGroupUUIDField.description == sharingGroupUUID) else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            XCTAssert(result.sharingGroupUUID == sharingGroupUUID)
            exp.fulfill()
        }
        
        handlers.userEvent = { _, error in
            XCTFail("\(String(describing: error))")
            exp.fulfill()
        }
        
        syncServer.getIndex(sharingGroupUUID: sharingGroupUUID)

        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testIndexCalledFromSyncServer() throws {
        let sharingGroupUUID = try getSharingGroupUUID()

        let exp = expectation(description: "exp")
        
        handlers.syncCompleted = { _, result in
            guard case .index(let uuid, let index) = result else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            XCTAssert(sharingGroupUUID == uuid)
            XCTAssert(index.count == 0)
            guard let result = try? SharingEntry.fetchSingleRow(db: self.database, where: SharingEntry.sharingGroupUUIDField.description == sharingGroupUUID) else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            XCTAssert(result.sharingGroupUUID == sharingGroupUUID)
            exp.fulfill()
        }
        
        handlers.userEvent = { _, error in
            XCTFail()
            exp.fulfill()
        }
        
        try syncServer.sync(sharingGroupUUID: sharingGroupUUID)

        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testIndexCalledFromSyncServerWithOneFile() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let (uploadable, _) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID)
        
        guard uploadable.uploads.count == 1 else {
            XCTFail()
            return
        }
        let uploadableFile = uploadable.uploads[0]

        let exp = expectation(description: "exp")
        
        handlers.syncCompleted = { _, result in
            guard case .index(let uuid, let index) = result else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            XCTAssert(sharingGroupUUID == uuid)
            guard index.count == 1, index[0].downloads.count == 1 else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            XCTAssert(!index[0].deleted)
            XCTAssert(index[0].fileGroupUUID == uploadable.fileGroupUUID)
            XCTAssert(index[0].sharingGroupUUID == uploadable.sharingGroupUUID)
            XCTAssert(index[0].objectType == uploadable.objectType)

            let indexFile = index[0].downloads[0]
            XCTAssert(uploadableFile.uuid == indexFile.uuid)
            XCTAssert(uploadableFile.fileLabel == indexFile.fileLabel)
            XCTAssert(indexFile.fileVersion == 0)

            guard let result = try? SharingEntry.fetchSingleRow(db: self.database, where: SharingEntry.sharingGroupUUIDField.description == sharingGroupUUID) else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            XCTAssert(result.sharingGroupUUID == sharingGroupUUID)
            exp.fulfill()
        }
        
        handlers.userEvent = { _, error in
            XCTFail()
            exp.fulfill()
        }
        
        try syncServer.sync(sharingGroupUUID: sharingGroupUUID)

        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testMakeSureIndexUpdateForDeletedObjectHasDeletionFail() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        let (uploadable, example) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID)
        
        guard uploadable.uploads.count == 1 else {
            XCTFail()
            return
        }
        
        let exp = expectation(description: "exp")
        handlers.deletionCompleted = { _, _ in
            exp.fulfill()
        }
        
        try syncServer.queue(objectDeletion: uploadable.fileGroupUUID)
        waitForExpectations(timeout: 10, handler: nil)
        
        // Reset the database show a state *as if* another client instance had done the upload/deleteion.
        database = try Connection(.inMemory)
        let fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, requestable: FakeRequestable(), configuration: config, signIns: fakeSignIns, backgroundAsssertable: MainAppBackgroundTask())
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        syncServer.helperDelegate = self
        
        try syncServer.register(object: example)

        let exp2 = expectation(description: "exp2")
        handlers.syncCompleted = { _,_ in
            exp2.fulfill()
        }
        
        // Fetch the database state again.
        try syncServer.sync(sharingGroupUUID: sharingGroupUUID)
        waitForExpectations(timeout: 10, handler: nil)
        
        // This is as if another client attempts a deletion of a file after a sync where it learned about the deleted file for the first time.
        do {
            try syncServer.queue(objectDeletion: uploadable.fileGroupUUID)
        } catch let error {
            guard let syncServerError = error as? SyncServerError else {
                XCTFail()
                return
            }
            
            XCTAssert(syncServerError == SyncServerError.attemptToDeleteAnAlreadyDeletedFile)
            return
        }
        
        XCTFail()
    }
    
    func testMakeSureIndexUpdateForDeletedObjectHasUploadFail() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        let (objectUpload, example) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID)
        guard objectUpload.uploads.count == 1,
            let uploadFile = objectUpload.uploads.first else {
            XCTFail()
            return
        }

        let exp = expectation(description: "exp")
        handlers.deletionCompleted = { _, _ in
            exp.fulfill()
        }
        
        try syncServer.queue(objectDeletion: objectUpload.fileGroupUUID)
        waitForExpectations(timeout: 10, handler: nil)
        
        // Reset the database show a state *as if* another client instance had done the upload/deleteion.
        database = try Connection(.inMemory)
        let fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, requestable: FakeRequestable(), configuration: config, signIns: fakeSignIns, backgroundAsssertable: MainAppBackgroundTask())
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        syncServer.helperDelegate = self
        
        try syncServer.register(object: example)

        let exp2 = expectation(description: "exp2")
        handlers.syncCompleted = { _,_ in
            exp2.fulfill()
        }
        
        // Fetch the database state again.
        try syncServer.sync(sharingGroupUUID: sharingGroupUUID)
        waitForExpectations(timeout: 10, handler: nil)
        
        let fileUpload1 = FileUpload(fileLabel: uploadFile.fileLabel, mimeType: .text, dataSource: .copy(exampleTextFileURL), uuid: uploadFile.uuid)
        let upload = ObjectUpload(objectType: objectUpload.objectType, fileGroupUUID: objectUpload.fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload1])

        // This is as if another client attempts an upload of a file after a sync where it learned about the deleted file for the first time.
        do {
            try syncServer.queue(upload: upload)
        } catch let error {
            guard let syncServerError = error as? SyncServerError else {
                XCTFail()
                return
            }
            
            XCTAssert(syncServerError == SyncServerError.attemptToQueueADeletedFile)
            return
        }
        
        XCTFail()
    }

    func testMakeSureIndexWithDeletedFileMarksAsDeleted() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        let (objectUpload, _) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID)
        guard objectUpload.uploads.count == 1,
            let uploadFile = objectUpload.uploads.first else {
            XCTFail()
            return
        }

        let exp = expectation(description: "exp")
        handlers.deletionCompleted = { _, _ in
            exp.fulfill()
        }
        
        try syncServer.queue(objectDeletion: objectUpload.fileGroupUUID)
        waitForExpectations(timeout: 10, handler: nil)
        
        // Reset the deleted state of the file.
        guard let fileEntry = try DirectoryFileEntry.fetchSingleRow(db: database, where: DirectoryFileEntry.fileUUIDField.description == uploadFile.uuid) else {
            XCTFail()
            return
        }
            
        guard let objectEntry = try DirectoryObjectEntry.fetchSingleRow(db: database, where: DirectoryObjectEntry.fileGroupUUIDField.description == objectUpload.fileGroupUUID) else {
            XCTFail()
            return
        }

        try fileEntry.update(setters:
            DirectoryFileEntry.deletedLocallyField.description <- false,
            DirectoryFileEntry.deletedOnServerField.description <- false)
            
        try objectEntry.update(setters:
            DirectoryObjectEntry.deletedLocallyField.description <- false,
            DirectoryObjectEntry.deletedOnServerField.description <- false)
        
        var resultIndex = [IndexObject]()
        
        let exp2 = expectation(description: "exp2")
        handlers.syncCompleted = { _, result in
            switch result {
            case .index(sharingGroupUUID: _, index: let index):
                resultIndex = index
            case .noIndex:
                XCTFail()
            }
            
            exp2.fulfill()
        }
        
        // Fetch the database state again.
        try syncServer.sync(sharingGroupUUID: sharingGroupUUID)
        waitForExpectations(timeout: 10, handler: nil)
        
        let filter = resultIndex.filter {$0.downloads.contains(where: {$0.uuid == uploadFile.uuid})}
        guard filter.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(filter[0].deleted)
        
        // The deleted state of the file should have been updated.
        guard let fileEntry2 = try DirectoryFileEntry.fetchSingleRow(db: database, where: DirectoryFileEntry.fileUUIDField.description == uploadFile.uuid) else {
            XCTFail()
            return
        }
            
        guard let objectEntry2 = try DirectoryObjectEntry.fetchSingleRow(db: database, where: DirectoryObjectEntry.fileGroupUUIDField.description == objectUpload.fileGroupUUID) else {
            XCTFail()
            return
        }
        
        XCTAssert(!fileEntry2.deletedLocally)
        XCTAssert(fileEntry2.deletedOnServer)
        XCTAssert(!objectEntry2.deletedLocally)
        XCTAssert(objectEntry2.deletedOnServer)
    }
    
    func testMakeSureSyncAfterUploadUpdatesCreationDate() throws {
        let startDate = Date()
        
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        let (uploadable, _) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID)
        
        guard uploadable.uploads.count == 1 else {
            XCTFail()
            return
        }
        
        guard let fileEntry = try DirectoryFileEntry.fetchSingleRow(db: database, where: DirectoryFileEntry.fileUUIDField.description == uploadable.uploads[0].uuid) else {
            XCTFail()
            return
        }
        
        var fileInfo = [IndexObject]()
        
        let exp = expectation(description: "exp2")

        handlers.syncCompleted = { _, result in
            guard case .index(_, let index) = result else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            fileInfo = index
            
            exp.fulfill()
        }

        // Fetch the database state again.
        try syncServer.sync(sharingGroupUUID: sharingGroupUUID)
        waitForExpectations(timeout: 10, handler: nil)
        
        // Get the object from the index containing the download with fileUUID: `uploadable.uploads[0].uuid`
        
        let filter = fileInfo.filter {$0.downloads.contains(where: {$0.uuid == uploadable.uploads[0].uuid})}
        guard filter.count == 1 else {
            XCTFail()
            return
        }
        
        let serverCreationDate = filter[0].creationDate
        
        XCTAssert(Date.approximatelyEqual(serverCreationDate, startDate, threshold: 5), "object.creationDate: \(serverCreationDate.timeIntervalSince1970); startDate: \(startDate.timeIntervalSince1970)")
        
        // This isn't really a logical assertion, but more of a practical assertion. Logically, the server creation date should be after the locally created entry *prior* to the sync. But, with clocks and data transfer precision changes, this isn't really a logical check.
        XCTAssert(fileEntry.creationDate != serverCreationDate)
        
        XCTAssert(Date.approximatelyEqual(serverCreationDate, fileEntry.creationDate, threshold: 5))
        
        guard let fileEntryAfter = try DirectoryFileEntry.fetchSingleRow(db: database, where: DirectoryFileEntry.fileUUIDField.description == uploadable.uploads[0].uuid) else {
            XCTFail()
            return
        }

        // Ensure that the database creationDate was updated.
        XCTAssert(fileEntry.creationDate != fileEntryAfter.creationDate)
    }
    
    func testMakeSureIndexForDownloadableFileHasCreationDate() throws {
        let startDate = Date()
        
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        let (uploadable, example) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID)
        
        guard uploadable.uploads.count == 1 else {
            XCTFail()
            return
        }
                
        // Reset the database show a state *as if* another client instance had done the upload/deleteion.
        database = try Connection(.inMemory)
        let fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, requestable: FakeRequestable(), configuration: config, signIns: fakeSignIns, backgroundAsssertable: MainAppBackgroundTask())
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        syncServer.helperDelegate = self
        
        try syncServer.register(object: example)

        let exp2 = expectation(description: "exp2")
        handlers.syncCompleted = { _,_ in
            exp2.fulfill()
        }
        
        // Fetch the database state again.
        try syncServer.sync(sharingGroupUUID: sharingGroupUUID)
        waitForExpectations(timeout: 10, handler: nil)
        
        guard let object = try syncServer.objectNeedsDownload(fileGroupUUID: uploadable.fileGroupUUID) else {
            XCTFail()
            return
        }
        
        XCTAssert(Date.approximatelyEqual(startDate, object.creationDate, threshold: 5), "object.creationDate: \(object.creationDate.timeIntervalSince1970); startDate: \(startDate.timeIntervalSince1970)")
    }

    func testTwoFilesInOneObjectInIndexWorks() throws {
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()
        let fileGroupUUID1 = UUID()

        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        let objectType1 = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: CommentFile.changeResolverName)
        let fileDeclaration2 = FileDeclaration(fileLabel: "file2", mimeTypes: [.text], changeResolverName: CommentFile.changeResolverName)
        let example1 = ExampleDeclaration(objectType: objectType1, declaredFiles: [fileDeclaration1, fileDeclaration2])
        try syncServer.register(object: example1)

        let commentFile = CommentFile()
        let commentFileData = try commentFile.getData()
        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .data(commentFileData), uuid: fileUUID1)
        let file2 = FileUpload(fileLabel: fileDeclaration2.fileLabel, mimeType: .text, dataSource: .data(commentFileData), uuid: fileUUID2)
        let upload1 = ObjectUpload(objectType: objectType1, fileGroupUUID: fileGroupUUID1, sharingGroupUUID: sharingGroupUUID, uploads: [file1, file2])
        try syncServer.queue(upload: upload1)

        waitForUploadsToComplete(numberUploads: 2)
    
        var fileInfo = [IndexObject]()
        
        let exp = expectation(description: "exp")

        handlers.syncCompleted = { _, result in
            guard case .index(_, let index) = result else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            fileInfo = index
            
            exp.fulfill()
        }

        // Fetch the database state again.
        try syncServer.sync(sharingGroupUUID: sharingGroupUUID)
        waitForExpectations(timeout: 10, handler: nil)
        
        guard fileInfo.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(!fileInfo[0].deleted)
        
        guard fileInfo[0].downloads.count == 2 else {
            XCTFail()
            return
        }
    }
    
    func testTwoObjectsInIndexWorks() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        let (uploadable1, _) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID)
        let (uploadable2, _) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID)
        
        var fileInfo = [IndexObject]()
        
        let exp = expectation(description: "exp")

        handlers.syncCompleted = { _, result in
            guard case .index(_, let index) = result else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            fileInfo = index
            
            exp.fulfill()
        }

        // Fetch the database state again.
        try syncServer.sync(sharingGroupUUID: sharingGroupUUID)
        waitForExpectations(timeout: 10, handler: nil)
        
        guard fileInfo.count == 2 else {
            XCTFail()
            return
        }
        
        let filter1 = fileInfo.filter {$0.fileGroupUUID == uploadable1.fileGroupUUID}
        let filter2 = fileInfo.filter {$0.fileGroupUUID == uploadable2.fileGroupUUID}
        
        guard filter1.count == 1 else {
            XCTFail()
            return
        }
        guard filter2.count == 1 else {
            XCTFail()
            return
        }
    }
    
    // MARK: Get content summary with index
    
    func testGetEmptyContentSummary() throws {
        let exp = expectation(description: "exp")
        
        handlers.syncCompleted = { _, result in
            guard case .noIndex(let sharingGroups) = result else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            guard sharingGroups.count == 1 else {
                XCTFail()
                return
            }
            
            guard let contentsSummary = sharingGroups[0].contentsSummary else {
                XCTFail()
                return
            }
            
            XCTAssert(contentsSummary.count == 0)
            
            exp.fulfill()
        }
        
        handlers.userEvent = { _, error in
            XCTFail()
            exp.fulfill()
        }
        
        try syncServer.sync(sharingGroupUUID: nil)

        waitForExpectations(timeout: 10, handler: nil)
    }
        
    func testGetContentSummaryWithOneFileGroup() throws {
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()
        let fileGroupUUID1 = UUID()

        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        let objectType1 = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: CommentFile.changeResolverName)
        let fileDeclaration2 = FileDeclaration(fileLabel: "file2", mimeTypes: [.text], changeResolverName: CommentFile.changeResolverName)
        let example1 = ExampleDeclaration(objectType: objectType1, declaredFiles: [fileDeclaration1, fileDeclaration2])
        try syncServer.register(object: example1)

        let commentFile = CommentFile()
        let commentFileData = try commentFile.getData()
        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .data(commentFileData), uuid: fileUUID1)
        let file2 = FileUpload(fileLabel: fileDeclaration2.fileLabel, mimeType: .text, dataSource: .data(commentFileData), uuid: fileUUID2)
        let upload1 = ObjectUpload(objectType: objectType1, fileGroupUUID: fileGroupUUID1, sharingGroupUUID: sharingGroupUUID, uploads: [file1, file2])
        try syncServer.queue(upload: upload1)

        waitForUploadsToComplete(numberUploads: 2)
        
        let exp = expectation(description: "exp")
        
        handlers.syncCompleted = { _, result in
            guard case .noIndex(let sharingGroups) = result else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            guard sharingGroups.count == 1 else {
                XCTFail()
                return
            }
            
            guard let contentsSummary = sharingGroups[0].contentsSummary else {
                XCTFail()
                return
            }
            
            guard contentsSummary.count == 1 else {
                XCTFail()
                return
            }
            
            XCTAssert(!contentsSummary[0].deleted)
            XCTAssert(contentsSummary[0].fileGroupUUID == fileGroupUUID1)

            exp.fulfill()
        }
        
        handlers.userEvent = { _, error in
            XCTFail()
            exp.fulfill()
        }
        
        try syncServer.sync(sharingGroupUUID: nil)

        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testGetContentSummaryWithTwoFileGroups() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        let _ = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID)
        let _ = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID)
        
        let exp = expectation(description: "exp")
        
        handlers.syncCompleted = { _, result in
            guard case .noIndex(let sharingGroups) = result else {
                XCTFail()
                exp.fulfill()
                return
            }
            
            guard sharingGroups.count == 1 else {
                XCTFail()
                return
            }
            
            guard sharingGroups[0].contentsSummary?.count == 2 else {
                XCTFail()
                return
            }

            exp.fulfill()
        }
        
        handlers.userEvent = { _, error in
            XCTFail()
            exp.fulfill()
        }
        
        try syncServer.sync(sharingGroupUUID: nil)

        waitForExpectations(timeout: 10, handler: nil)
    }
}
