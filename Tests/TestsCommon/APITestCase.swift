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
import ChangeResolvers

class DropboxKey: Codable {
    let DropboxAppKey: String
}

private var calledDropboxSetup = false

public struct ExampleComment {
    static let messageKey = "messageString"
    public let messageString:String
    public let id: String
    
    public var record:CommentFile.FixedObject {
        var result = CommentFile.FixedObject()
        result[CommentFile.idKey] = id
        result[Self.messageKey] = messageString
        return result
    }
    
    public var updateContents: Data {
        return try! JSONSerialization.data(withJSONObject: record)
    }
}

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

enum SelectUser {
    case first
    case second
}
    
extension UserSetup {
    var dropboxKeyURL: URL {
        URL(fileURLWithPath: "/Users/chris/Developer/Private/iOSBasics/DropboxKey.json")
    }

    // First dropbox user
    var dropboxCredentialsPath: String { return "/Users/chris/Developer/Private/iOSBasics/Dropbox.credentials"
    }
    
    // Second dropbox user
    var dropboxCredentialsPath2: String { return "/Users/chris/Developer/Private/iOSBasics/Dropbox2.credentials"
    }

    // Dropbox
    
    // Add the current user.
    @discardableResult
    private func addDropboxUser() -> Bool {
        let exp = expectation(description: "exp")
        
        var success = true
        let uuid = UUID()
        
        api.addUser(cloudFolderName: nil, sharingGroupUUID: uuid, sharingGroupName: nil) { result in
            switch result {
            case .success(let result):
                guard case .userId = result else {
                    success = false
                    return
                }
            case .failure(let error):
                logger.error("\(error)")
                success = false
            }
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        
        return success
    }

    // Remove the current signed in user.
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

    private func createDropboxCredentials(selectUser: SelectUser = .first) throws -> DropboxCredentials {
        let dropboxCredentials:URL
        
        let keyData = try Data(contentsOf: dropboxKeyURL)
        let key = try JSONDecoder().decode(DropboxKey.self, from: keyData)
        
        // This does necessary initializations for Dropbox-- so that token can be refreshed.
        // Have to futz around here. Can only call this once.
        if !calledDropboxSetup {
            _ = DropboxSyncServerSignIn(appKey: key.DropboxAppKey)
            calledDropboxSetup = true
        }
        
        switch selectUser {
        case .first:
            dropboxCredentials = URL(fileURLWithPath: dropboxCredentialsPath)
        case .second:
            dropboxCredentials = URL(fileURLWithPath: dropboxCredentialsPath2)
        }
        
        let savedCreds = try DropboxSavedCreds.fromJSON(file: dropboxCredentials)
        let creds = DropboxCredentials(savedCreds:savedCreds)

        let exp = expectation(description: "exp")
        creds.refreshCredentials { error in
            XCTAssert(error == nil, "\(String(describing: error))")
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
        return creds
    }

    func dropboxUser(selectUser: SelectUser = .first) throws -> TestUser {
        let creds = try createDropboxCredentials(selectUser: selectUser)
        return TestUser(
            cloudStorageType: .Dropbox,
            credentials:creds,
            hashing: DropboxHashing(),
            removeUser: removeDropboxUser,
            addUser: addDropboxUser
        )
    }
}
