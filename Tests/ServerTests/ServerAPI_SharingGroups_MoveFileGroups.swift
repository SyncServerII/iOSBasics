//
//  ServerAPI_SharingGroups_MoveFileGroups.swift
//  ServerTests
//
//  Created by Christopher G Prince on 7/9/21.
//

import XCTest
@testable import iOSBasics
import iOSSignIn
@testable import iOSDropbox
import ServerShared
import iOSShared
import SQLite
@testable import TestsCommon

class ServerAPI_SharingGroups_MoveFileGroups: XCTestCase, UserSetup, APITests, ServerAPIDelegator, ServerBasics, TestFiles {
    var hashingManager: HashingManager!
    var api: ServerAPI!
    var deviceUUID: UUID!
    var database: Connection!
    let config = Configuration.defaultTemporaryFiles
    var handlers = DelegateHandlers()
    var user2:TestUser!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        handlers = DelegateHandlers()
        user2 = try dropboxUser(selectUser: .second)
        handlers.user = try dropboxUser()
        deviceUUID = UUID()
        let database = try Connection(.inMemory)
        try NetworkCache.createTable(db: database)
        let config = Configuration(appGroupIdentifier: nil, serverURL: URL(string: Self.baseURL())!, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true, deferredCheckInterval: nil)
        hashingManager = HashingManager()
        try? hashingManager.add(hashing: DropboxHashing())
        let serialQueue = DispatchQueue(label: "iOSBasicsTests")
        let backgroundAssertable = MainAppBackgroundTask()
        api = ServerAPI(database: database, hashingManager: hashingManager, delegate: self, serialQueue: serialQueue, backgroundAsssertable: backgroundAssertable, config: config)
        _ = handlers.user.removeUser()
        XCTAssert(handlers.user.addUser())
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testMoveOneFileGroup() throws {
        let fileUUID = UUID()

        let fileURL = exampleTextFileURL
        
        let checkSum = try hashingManager.hashFor(cloudStorageType: handlers.user.cloudStorageType).hash(forURL: fileURL)
        
        guard let result = getIndex(sharingGroupUUID: nil),
            result.sharingGroups.count > 0,
            let sharingGroupUUID = result.sharingGroups[0].sharingGroupUUID else {
            XCTFail()
            return
        }
        
        let fileGroup = ServerAPI.File.Version.FileGroup(fileGroupUUID: UUID(), objectType: "Foobar")
        let file = ServerAPI.File(fileUUID: fileUUID.uuidString, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID.uuidString, uploadObjectTrackerId: -1, batchUUID: UUID(), batchExpiryInterval: 100, version: .v0(url: fileURL, mimeType: MimeType.text, checkSum: checkSum, changeResolverName: nil, fileGroup: fileGroup, appMetaData: nil, fileLabel: UUID().uuidString))
        
        guard let uploadResult = uploadFile(file: file, uploadIndex: 1, uploadCount: 1) else {
            XCTFail()
            return
        }
        
        switch uploadResult {
        case .success:
            break
        default:
            XCTFail()
            return
        }
        
        let destSharingGroupUUID = UUID()
        var createdSharingGroup = false
        
        let exp1 = expectation(description: "exp")
        api.createSharingGroup(sharingGroup: destSharingGroupUUID) { error in
            XCTAssert(error == nil)
            if error == nil {
                createdSharingGroup = true
            }
            exp1.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        guard createdSharingGroup else {
            XCTFail()
            return
        }

        guard let sourceSharingGroup = UUID(uuidString: sharingGroupUUID) else {
            XCTFail()
            return
        }

        var moveSucceeded = false

        let exp2 = expectation(description: "exp")
        api.moveFileGroups([fileGroup.fileGroupUUID], fromSourceSharingGroup: sourceSharingGroup, toDestinationSharingGroup: destSharingGroupUUID) { result in
            switch result {
            case .failure(let error):
                XCTFail("\(error)")
            case .success(let response):
                switch response.result {
                case .success:
                    moveSucceeded = true
                case .failedWithNotAllOwnersInTarget, .failedWithUserConstraintNotSatisfied:
                    XCTFail()
                case .none:
                    XCTFail()
                }
                
            }
            exp2.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)

        guard moveSucceeded else {
            XCTFail()
            return
        }
        
        guard let result2 = getIndex(sharingGroupUUID: destSharingGroupUUID) else {
            XCTFail()
            return
        }
        
        guard let fileIndex = result2.fileIndex else {
            XCTFail()
            return
        }
        
        guard fileIndex.count == 1 else {
            XCTFail()
            return
        }
        
        let fileInfo = fileIndex[0]
        XCTAssert(fileInfo.fileGroupUUID == fileGroup.fileGroupUUID.uuidString)
    }
    
    func testMoveTwoFileGroups() throws {
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()
        let fileGroup1 = ServerAPI.File.Version.FileGroup(fileGroupUUID: UUID(), objectType: "Foobar1")
        let fileGroup2 = ServerAPI.File.Version.FileGroup(fileGroupUUID: UUID(), objectType: "Foobar2")

        let fileURL = exampleTextFileURL
        
        let checkSum = try hashingManager.hashFor(cloudStorageType: handlers.user.cloudStorageType).hash(forURL: fileURL)
        
        guard let result = getIndex(sharingGroupUUID: nil),
            result.sharingGroups.count > 0,
            let sharingGroupUUID = result.sharingGroups[0].sharingGroupUUID else {
            XCTFail()
            return
        }
        
        let file1 = ServerAPI.File(fileUUID: fileUUID1.uuidString, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID.uuidString, uploadObjectTrackerId: -1, batchUUID: UUID(), batchExpiryInterval: 100, version: .v0(url: fileURL, mimeType: MimeType.text, checkSum: checkSum, changeResolverName: nil, fileGroup: fileGroup1, appMetaData: nil, fileLabel: UUID().uuidString))
        
        guard let uploadResult1 = uploadFile(file: file1, uploadIndex: 1, uploadCount: 1) else {
            XCTFail()
            return
        }
        
        switch uploadResult1 {
        case .success:
            break
        default:
            XCTFail()
            return
        }

        let file2 = ServerAPI.File(fileUUID: fileUUID2.uuidString, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID.uuidString, uploadObjectTrackerId: -1, batchUUID: UUID(), batchExpiryInterval: 100, version: .v0(url: fileURL, mimeType: MimeType.text, checkSum: checkSum, changeResolverName: nil, fileGroup: fileGroup2, appMetaData: nil, fileLabel: UUID().uuidString))
        
        guard let uploadResult2 = uploadFile(file: file2, uploadIndex: 1, uploadCount: 1) else {
            XCTFail()
            return
        }
        
        switch uploadResult2 {
        case .success:
            break
        default:
            XCTFail()
            return
        }
        
        let destSharingGroupUUID = UUID()
        var createdSharingGroup = false
        
        let exp1 = expectation(description: "exp")
        api.createSharingGroup(sharingGroup: destSharingGroupUUID) { error in
            XCTAssert(error == nil)
            if error == nil {
                createdSharingGroup = true
            }
            exp1.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        
        guard createdSharingGroup else {
            XCTFail()
            return
        }

        guard let sourceSharingGroup = UUID(uuidString: sharingGroupUUID) else {
            XCTFail()
            return
        }

        var moveSucceeded = false

        let exp2 = expectation(description: "exp")
        api.moveFileGroups([fileGroup1.fileGroupUUID, fileGroup2.fileGroupUUID], fromSourceSharingGroup: sourceSharingGroup, toDestinationSharingGroup: destSharingGroupUUID) { result in
            switch result {
            case .failure(let error):
                XCTFail("\(error)")
            case .success(let response):
                switch response.result {
                case .success:
                    moveSucceeded = true
                case .failedWithNotAllOwnersInTarget, .failedWithUserConstraintNotSatisfied:
                    XCTFail()
                case .none:
                    XCTFail()
                }
                
            }
            exp2.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)

        guard moveSucceeded else {
            XCTFail()
            return
        }
        
        guard let result2 = getIndex(sharingGroupUUID: destSharingGroupUUID) else {
            XCTFail()
            return
        }
        
        guard let fileIndex = result2.fileIndex else {
            XCTFail()
            return
        }
        
        guard fileIndex.count == 2 else {
            XCTFail()
            return
        }
        
        let filter1 = fileIndex.filter { $0.fileGroupUUID == fileGroup1.fileGroupUUID.uuidString }
        let filter2 = fileIndex.filter { $0.fileGroupUUID == fileGroup2.fileGroupUUID.uuidString }
        
        guard filter1.count == 1, filter2.count == 1 else {
            XCTFail()
            return
        }
    }
}
