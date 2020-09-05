//
//  File.swift
//  
//
//  Created by Christopher G Prince on 8/31/20.
//

import Foundation
import XCTest
@testable import iOSBasics
import iOSSignIn
import iOSShared
import ServerShared
import SQLite
@testable import iOSDropbox

struct TestUser {
    let cloudStorageType: CloudStorageType
    let credentials:GenericCredentials
    let hashing: CloudStorageHashing
    let removeUser:()->(Bool)
    let addUser:()->(Bool)
}

protocol UserSetup where Self: XCTestCase {
    var api:ServerAPI! {get}
}

extension UserSetup {
    // A bit of a hack
    var dropboxCredentialsPath: String { return "/Users/chris/Desktop/NewSyncServer/Private/iOSBasics/Dropbox.credentials"
    }

    // Dropbox
    
    @discardableResult
    private func addDropboxUser() -> Bool {
        let exp = expectation(description: "exp")
        
        var success = true
        let uuid = UUID()
        
        api.addUser(cloudFolderName: nil, sharingGroupUUID: uuid, sharingGroupName: nil) { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                success = false
            }
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        
        return success
    }

    @discardableResult
    private func removeDropboxUser() -> Bool {
        let exp = expectation(description: "exp")
        
        var success = true
        
        api.removeUser { error in
            success = error == nil
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        
        return success
    }
    
    private func createDropboxCredentials() throws -> DropboxCredentials {
        let savedCredentials = try loadDropboxCredentials()
        return DropboxCredentials(savedCreds:savedCredentials)
    }
    
    private func loadDropboxCredentials() throws -> DropboxSavedCreds {
        let dropboxCredentials = URL(fileURLWithPath: dropboxCredentialsPath)
        return try DropboxSavedCreds.fromJSON(file: dropboxCredentials)
    }
    
    private func setupDropboxCredentials() throws -> DropboxCredentials {
        let savedCredentials = try loadDropboxCredentials()
        return DropboxCredentials(savedCreds:savedCredentials)
    }
    
    func dropboxUser() throws -> TestUser {
        let creds = try setupDropboxCredentials()
        return TestUser(
            cloudStorageType: .Dropbox,
            credentials:creds,
            hashing: DropboxHashing(),
            removeUser: removeDropboxUser,
            addUser: addDropboxUser
        )
    }
}
