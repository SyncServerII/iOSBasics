//
//  SharingInvitationTests.swift
//  ServerTests
//
//  Created by Christopher G Prince on 9/27/20.
//

import XCTest


import XCTest
@testable import iOSBasics
import iOSSignIn
@testable import iOSDropbox
import ServerShared
import iOSShared
import SQLite

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
        let config = Configuration(appGroupIdentifier: nil, serverURL: URL(string: Self.baseURL())!, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true)
        hashingManager = HashingManager()
        try? hashingManager.add(hashing: DropboxHashing())
        api = ServerAPI(database: database, hashingManager: hashingManager, delegate: self, config: config)
        _ = handlers.user.removeUser()
        XCTAssert(handlers.user.addUser())
    }

    override func tearDownWithError() throws {
    }

    func createSharingInvitation(permission:Permission = .admin, sharingGroupUUID: UUID) -> UUID? {
    
        var sharingInvitationUUID: UUID?
        
        let exp = expectation(description: "exp")
        
        api.createSharingInvitation(withPermission: permission, sharingGroupUUID: sharingGroupUUID, numberAcceptors: 1, allowSharingAcceptance: true) { result in
            
            switch result {
            case .failure:
                break
            case .success(let code):
                sharingInvitationUUID = code
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        
        return sharingInvitationUUID
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
    
    func testRedeemExistingSharingInvitationByNonCreatingUserWorks() {
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
            case .success:
                break
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
