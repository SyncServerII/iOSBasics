//
//  SharingInvitationTests.swift
//  ServerTests
//
//  Created by Christopher G Prince on 9/27/20.
//

import XCTest
@testable import iOSBasics
import iOSSignIn
@testable import iOSDropbox
import ServerShared
import iOSShared
import SQLite
@testable import TestsCommon

class SharingInvitationTests: XCTestCase, UserSetup, APITests, ServerAPIDelegator, ServerBasics, TestFiles {
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
        handlers.user = try dropboxUser()
        user2 = try dropboxUser(selectUser: .second)
        deviceUUID = UUID()
        let database = try Connection(.inMemory)
        try NetworkCache.createTable(db: database)
        let config = Configuration(appGroupIdentifier: nil, serverURL: URL(string: Self.baseURL())!, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true, deferredCheckInterval: nil)
        hashingManager = HashingManager()
        try? hashingManager.add(hashing: DropboxHashing())
        let serialQueue = DispatchQueue(label: "iOSBasicsTests")
        api = ServerAPI(database: database, hashingManager: hashingManager, delegate: self, serialQueue: serialQueue, backgroundAsssertable: MainAppBackgroundTask(), config: config)
        _ = handlers.user.removeUser()
        XCTAssert(handlers.user.addUser())
    }

    override func tearDownWithError() throws {
    }
    
    func testCreateSharingInvitation() throws {
        guard let result = getIndex(sharingGroupUUID: nil),
            result.sharingGroups.count > 0,
            let sharingGroupUUIDString = result.sharingGroups[0].sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard let sharingGroupUUID = UUID(uuidString: sharingGroupUUIDString) else {
            XCTFail()
            return
        }
        
        guard let _ = createSharingInvitation(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
    }
    
    func testGetSharingInvitationInfoWithExistingInvitation() {
        guard let result = getIndex(sharingGroupUUID: nil),
            result.sharingGroups.count > 0,
            let sharingGroupUUIDString = result.sharingGroups[0].sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard let sharingGroupUUID = UUID(uuidString: sharingGroupUUIDString) else {
            XCTFail()
            return
        }
        
        guard let invitationCode = createSharingInvitation(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let exp = expectation(description: "exp")
        
        api.getSharingInvitationInfo(sharingInvitationUUID: invitationCode) { result in
        
            switch result {
            case .failure:
                XCTFail()
            case .success(let info):
                switch info {
                case .invitation:
                    break
                case .noInvitationFound:
                    XCTFail()
                }
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testGetSharingInvitationInfoWithNonExistentInvitation() {
        let invitationCode = UUID()
        
        let exp = expectation(description: "exp")
        
        api.getSharingInvitationInfo(sharingInvitationUUID: invitationCode) { result in
        
            switch result {
            case .failure:
                XCTFail()
            case .success(let info):
                switch info {
                case .invitation:
                    XCTFail()
                case .noInvitationFound:
                    break
                }
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testRedeemExistingSharingInvitationByCreatingUserFails() {
        guard let result = getIndex(sharingGroupUUID: nil),
            result.sharingGroups.count > 0,
            let sharingGroupUUIDString = result.sharingGroups[0].sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard let sharingGroupUUID = UUID(uuidString: sharingGroupUUIDString) else {
            XCTFail()
            return
        }
        
        guard let code = createSharingInvitation(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        // Redeeming by the same user should fail.
        
        let exp = expectation(description: "exp")
        
        api.redeemSharingInvitation(sharingInvitationUUID: code, cloudFolderName: nil) { result in
        
            switch result {
            case .failure:
                break
            case .success:
                XCTFail()
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testRedeemExistingSharingInvitationByNewUserWorks() {
        guard let result = getIndex(sharingGroupUUID: nil),
            result.sharingGroups.count > 0,
            let sharingGroupUUIDString = result.sharingGroups[0].sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard let sharingGroupUUID = UUID(uuidString: sharingGroupUUIDString) else {
            XCTFail()
            return
        }
        
        guard let code = createSharingInvitation(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        // Switch over to 2nd user to redeem the invitation.
        handlers.user = user2
        
        let exp = expectation(description: "exp")
        
        api.redeemSharingInvitation(sharingInvitationUUID: code, cloudFolderName: nil) { result in
        
            switch result {
            case .failure:
                XCTFail()
            case .success(let result):
                XCTAssert(result.userCreated)
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        
        XCTAssert(handlers.user.removeUser())
    }
    
    func testRedeemExistingSharingInvitationByExistingUserWorks() {
        guard let result = getIndex(sharingGroupUUID: nil),
            result.sharingGroups.count > 0,
            let sharingGroupUUIDString = result.sharingGroups[0].sharingGroupUUID else {
            XCTFail()
            return
        }
        
        guard let sharingGroupUUID = UUID(uuidString: sharingGroupUUIDString) else {
            XCTFail()
            return
        }
        
        guard let code = createSharingInvitation(sharingGroupUUID: sharingGroupUUID) else {
            XCTFail()
            return
        }

        // Switch over to 2nd user to redeem the invitation.
        handlers.user = user2

        // Add that user first.
        _ = handlers.user.removeUser()
        XCTAssert(handlers.user.addUser())
        
        let exp = expectation(description: "exp")
        
        api.redeemSharingInvitation(sharingInvitationUUID: code, cloudFolderName: nil) { result in
        
            switch result {
            case .failure:
                XCTFail()
            case .success(let result):
                XCTAssert(!result.userCreated)
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        
        XCTAssert(handlers.user.removeUser())
    }
    
    func testRedeemNonExistingSharingInvitationFails() {
        let code = UUID()
        
        let exp = expectation(description: "exp")
        
        api.redeemSharingInvitation(sharingInvitationUUID: code, cloudFolderName: nil) { result in
        
            switch result {
            case .failure:
                break
            case .success:
                XCTFail()
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
}
