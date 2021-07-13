//
//  SharingGroupTests_MoveFileGroups.swift
//  SyncServerTests
//
//  Created by Christopher G Prince on 7/9/21.
//

import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn
import ChangeResolvers
@testable import TestsCommon

class SharingGroupTests_MoveFileGroups: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, Delegate, SyncServerTests {
    var handlers = DelegateHandlers()
    var deviceUUID: UUID!
    var hashingManager: HashingManager!
    var api: ServerAPI!
    var syncServer: SyncServer!
    var fakeHelper:SignInServicesHelperFake!
    var database: Connection!
    var config:Configuration!
    var user2: TestUser!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        handlers = DelegateHandlers()
        handlers.user = try dropboxUser()
        user2 = try dropboxUser(selectUser: .second)
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
        
        syncServer.helperDelegate = self
        handlers.objectType = { _, _ in
            return nil
        }
    }

    override func tearDownWithError() throws {
        // All temporary files should have been removed prior to end of test.
        let filePaths = try FileManager.default.contentsOfDirectory(atPath: config.temporaryFiles.directory.path)
        XCTAssert(filePaths.count == 0, "\(filePaths.count)")
        
        let count = try NetworkCache.numberRows(db: database)
        XCTAssert(count == 0, "\(count)")
    }

    // A point of this test is to make sure DirectoryObjectEntry's and any other db objects are changed correctly afterwards. DirectoryObjectEntry relate fileGroupUUID's to sharingGroupUUID's
    func testCurrentClientMovesFileGroupsAndSyncs() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        let destSharingGroupUUID = UUID()

        let (uploadable1, _) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID)
        
        var createdSharingGroup = false
        let exp = expectation(description: "exp")
        syncServer.createSharingGroup(sharingGroupUUID: destSharingGroupUUID) { error in
            XCTAssert(error == nil, "\(String(describing: error))")
            createdSharingGroup = error == nil
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        guard createdSharingGroup else {
            XCTFail()
            return
        }

        let exp2 = expectation(description: "exp2")
        var moveResult : SyncServer.MoveFileGroupsResult?
        
        syncServer.moveFileGroups([uploadable1.fileGroupUUID], fromSourceSharingGroup: sharingGroupUUID, toDestinationSharingGroup: destSharingGroupUUID) { result in
            moveResult = result
            exp2.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        switch moveResult {
        case .success:
            break
        default:
            XCTFail()
            return
        }
        
        guard let index1 = getIndex(sharingGroupUUID: sharingGroupUUID),
            let fileIndex1 = index1.fileIndex else {
            XCTFail()
            return
        }

        guard let index2 = getIndex(sharingGroupUUID: destSharingGroupUUID),
            let fileIndex2 = index2.fileIndex else {
            XCTFail()
            return
        }
        
        let filter1 = fileIndex1.filter { $0.fileGroupUUID == uploadable1.fileGroupUUID.uuidString}
        let filter2 = fileIndex2.filter { $0.fileGroupUUID == uploadable1.fileGroupUUID.uuidString}

        guard filter1.count == 0 else {
            XCTFail()
            return
        }
        
        guard filter2.count == 1 else {
            XCTFail()
            return
        }
    }
    
    // We need to be able to do a sync after someone else does a file group move and end up in a consistent state.
    func testOtherClientMovesFileGroupsAndWeSync() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        let destSharingGroupUUID = UUID()

        let (uploadable1, example) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID)
        
        var createdSharingGroup = false
        let exp = expectation(description: "exp")
        syncServer.createSharingGroup(sharingGroupUUID: destSharingGroupUUID) { error in
            XCTAssert(error == nil, "\(String(describing: error))")
            createdSharingGroup = error == nil
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        guard createdSharingGroup else {
            XCTFail()
            return
        }

        let exp2 = expectation(description: "exp2")
        var moveResult : SyncServer.MoveFileGroupsResult?
        
        syncServer.moveFileGroups([uploadable1.fileGroupUUID], fromSourceSharingGroup: sharingGroupUUID, toDestinationSharingGroup: destSharingGroupUUID) { result in
            moveResult = result
            exp2.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        switch moveResult {
        case .success:
            break
        default:
            XCTFail()
            return
        }
        
        // Reset the database show a state *as if* another client instance had done the upload/deleteion.
        database = try Connection(.inMemory)
        let fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, requestable: FakeRequestable(), configuration: config, signIns: fakeSignIns, backgroundAsssertable: MainAppBackgroundTask(), migrationRunner: MigrationRunnerFake())
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        syncServer.helperDelegate = self
        
        try syncServer.register(object: example)
        
        guard let index1 = getIndex(sharingGroupUUID: sharingGroupUUID),
            let fileIndex1 = index1.fileIndex else {
            XCTFail()
            return
        }

        guard let index2 = getIndex(sharingGroupUUID: destSharingGroupUUID),
            let fileIndex2 = index2.fileIndex else {
            XCTFail()
            return
        }
        
        let filter1 = fileIndex1.filter { $0.fileGroupUUID == uploadable1.fileGroupUUID.uuidString}
        let filter2 = fileIndex2.filter { $0.fileGroupUUID == uploadable1.fileGroupUUID.uuidString}

        guard filter1.count == 0 else {
            XCTFail()
            return
        }
        
        guard filter2.count == 1 else {
            XCTFail()
            return
        }
    }
    
    func testMoveMultipleFileGroups() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        let destSharingGroupUUID = UUID()

        let (uploadable1, _) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID)
        let (uploadable2, _) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID)
        
        var createdSharingGroup = false
        let exp = expectation(description: "exp")
        syncServer.createSharingGroup(sharingGroupUUID: destSharingGroupUUID) { error in
            XCTAssert(error == nil, "\(String(describing: error))")
            createdSharingGroup = error == nil
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        guard createdSharingGroup else {
            XCTFail()
            return
        }

        guard let index0 = getIndex(sharingGroupUUID: sharingGroupUUID),
            let fileIndex0 = index0.fileIndex else {
            XCTFail()
            return
        }

        guard fileIndex0.count == 2 else {
            XCTFail()
            return
        }
        
        let exp2 = expectation(description: "exp2")
        var moveResult : SyncServer.MoveFileGroupsResult?
        
        syncServer.moveFileGroups([uploadable1.fileGroupUUID, uploadable2.fileGroupUUID], fromSourceSharingGroup: sharingGroupUUID, toDestinationSharingGroup: destSharingGroupUUID) { result in
            moveResult = result
            exp2.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        switch moveResult {
        case .success:
            break
        default:
            XCTFail()
            return
        }
        
        guard let index1 = getIndex(sharingGroupUUID: sharingGroupUUID),
            let fileIndex1 = index1.fileIndex else {
            XCTFail()
            return
        }

        guard let index2 = getIndex(sharingGroupUUID: destSharingGroupUUID),
            let fileIndex2 = index2.fileIndex else {
            XCTFail()
            return
        }

        guard fileIndex1.count == 0 else {
            XCTFail()
            return
        }
        
        guard fileIndex2.count == 2 else {
            XCTFail()
            return
        }
    }

    // Queue a deletion; try to do a move of that file group. It should fail.
    func testQueuedDeletionCausesMoveToFail() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        let destSharingGroupUUID = UUID()

        let (uploadable1, _) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID)
        
        var createdSharingGroup = false
        let exp = expectation(description: "exp")
        syncServer.createSharingGroup(sharingGroupUUID: destSharingGroupUUID) { error in
            XCTAssert(error == nil, "\(String(describing: error))")
            createdSharingGroup = error == nil
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        guard createdSharingGroup else {
            XCTFail()
            return
        }

        try syncServer.queue(objectDeletion: uploadable1.fileGroupUUID)

        let exp2 = expectation(description: "exp2")
        var moveResult : SyncServer.MoveFileGroupsResult?
        
        syncServer.moveFileGroups([uploadable1.fileGroupUUID], fromSourceSharingGroup: sharingGroupUUID, toDestinationSharingGroup: destSharingGroupUUID) { result in
            moveResult = result
            exp2.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        switch moveResult {
        case .currentDeletions:
            break
        default:
            XCTFail()
            return
        }
        
        // Need to wait for deletion to complete.
        let exp3 = expectation(description: "exp")
        handlers.deletionCompleted = { _, _ in
            exp3.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        // Wait for some period of time for the deferred deletion to complete.
        Thread.sleep(forTimeInterval: 5)
        
        // This `sync` is to trigger the check for the deferred upload completion.
        try syncServer.sync()
        
        let exp4 = expectation(description: "exp2")
        handlers.deferredCompleted = { _, operation, fileGroupUUIDs in
            XCTAssert(operation == .deletion)
            XCTAssert(fileGroupUUIDs.count == 1)
            exp4.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
    }

    // Queue an upload; try to do a move. It should fail.
    func testQueuedUploadCausesMoveToFail() throws {
        let fileUUID = UUID()
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let changeResolver = CommentFile.changeResolverName
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: changeResolver)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let commentFile = CommentFile()
        let commentFileData = try commentFile.getData()
                
        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .data(commentFileData), uuid: fileUUID)
        let uploads = [file1]
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: uploads)

        try syncServer.queue(upload: upload)
        waitForUploadsToComplete(numberUploads: 1)
        
        let destSharingGroupUUID = UUID()
        
        var createdSharingGroup = false
        let exp = expectation(description: "exp")
        syncServer.createSharingGroup(sharingGroupUUID: destSharingGroupUUID) { error in
            XCTAssert(error == nil, "\(String(describing: error))")
            createdSharingGroup = error == nil
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        guard createdSharingGroup else {
            XCTFail()
            return
        }
        
        let exp2 = expectation(description: "exp2")
        
        let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        
        let file2 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .data(comment.updateContents), uuid: fileUUID)
        let uploads2 = [file2]
        
        let upload2 = ObjectUpload(objectType: objectType, fileGroupUUID: upload.fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: uploads2)
        
        try syncServer.queue(upload: upload2)
        
        var moveResult : SyncServer.MoveFileGroupsResult?
        
        syncServer.moveFileGroups([upload.fileGroupUUID], fromSourceSharingGroup: sharingGroupUUID, toDestinationSharingGroup: destSharingGroupUUID) { result in
            moveResult = result
            exp2.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)

        switch moveResult {
        case .currentUploads:
            break
        default:
            XCTFail()
            return
        }
        
        waitForUploadsToComplete(numberUploads: 1)
        
        // Wait for some period of time for the deferred upload to complete.
        Thread.sleep(forTimeInterval: 5)
        
        // This `sync` is to trigger the check for the deferred upload completion.
        try syncServer.sync()

        let exp3 = expectation(description: "exp2")
        handlers.deferredCompleted = { _, operation, count in
            exp3.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testFailedWithNotAllOwnersInTarget() throws {
        // Plan:
        // a) Get user2 into sharingGroupUUID-- we'll have both users this sharing group.
        // b) Have user1 do the upload to sharingGroupUUID
        // c) Have user2 do the file group move
        
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let (uploadable1, _) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID)

        let permission:Permission = .admin
        
        var code: UUID!

        let exp = expectation(description: "exp")
        syncServer.createSharingInvitation(withPermission: permission, sharingGroupUUID: sharingGroupUUID, numberAcceptors: 1, allowSocialAcceptance: false) { result in
            switch result {
            case .success(let uuid):
                code = uuid
            case .failure:
                XCTFail()
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)


        guard code != nil else {
            XCTFail()
            return
        }
        
        let firstUser = handlers.user
        handlers.user = user2
        
        let exp2 = expectation(description: "exp2")
        syncServer.redeemSharingInvitation(sharingInvitationUUID: code) { result in
            switch result {
            case .success:
                break
            case .failure:
                XCTFail()
            }
            exp2.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
       
        // user2-- create the dest sharing group
        let destSharingGroupUUID = UUID()

        var createdSharingGroup = false
        let exp3 = expectation(description: "exp3")
        syncServer.createSharingGroup(sharingGroupUUID: destSharingGroupUUID) { error in
            XCTAssert(error == nil, "\(String(describing: error))")
            createdSharingGroup = error == nil
            exp3.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
      
        guard createdSharingGroup else {
            XCTFail()
            return
        }
   
        // user2 -- attempt the move
        
        let exp4 = expectation(description: "exp4")
        var moveResult : SyncServer.MoveFileGroupsResult?
        
        syncServer.moveFileGroups([uploadable1.fileGroupUUID], fromSourceSharingGroup: sharingGroupUUID, toDestinationSharingGroup: destSharingGroupUUID) { result in
            moveResult = result
            exp4.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        switch moveResult {
        case .failedWithNotAllOwnersInTarget:
            break
        default:
            XCTFail("\(String(describing: moveResult))")
            return
        }
        
        XCTAssert(user2.removeUser())
    }
}
