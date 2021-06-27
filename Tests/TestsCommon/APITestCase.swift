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
@testable import iOSGoogle
import ChangeResolvers

class DropboxKey: Codable {
    let DropboxAppKey: String
}

class GoogleKey: Codable {
    let GoogleClientId: String
	let GoogleServerClientId: String
}

private var calledDropboxSetup = false
private var calledGoogleSetup = false

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

protocol UserSetup: GoogleSignInDelegate where Self: XCTestCase {
    var api:ServerAPI! {get}
}

enum SelectUser {
    case first
    case second
}
    
extension UserSetup {
    var googleKeyURL: URL {
        URL(fileURLWithPath: "/Users/chris/Developer/Private/iOSBasics/GoogleKey.json")
    }
    
    var dropboxKeyURL: URL {
        URL(fileURLWithPath: "/Users/chris/Developer/Private/iOSBasics/DropboxKey.json")
    }

    // Manually removed the serverAuthCode from this file-- as it was causing problems on the server. I think because I got these creds from Neebla and the server auth code had already been used.
    var googleCredentialsPath: String { return "/Users/chris/Developer/Private/iOSBasics/Google.credentials"
    }
    
    // First dropbox user
    var dropboxCredentialsPath: String { return "/Users/chris/Developer/Private/iOSBasics/Dropbox.credentials"
    }
    
    // Second dropbox user
    var dropboxCredentialsPath2: String { return "/Users/chris/Developer/Private/iOSBasics/Dropbox2.credentials"
    }
    
    var cloudFolderName: String {
        return "iOSBasics.Tests"
    }
    
    // Add the current user.
    @discardableResult
    private func addUser() -> Bool {
        return addUser(withEmailAddress: nil)
    }

    @discardableResult
    func addUser(withEmailAddress emailAddress: String?) -> Bool {
        let exp = expectation(description: "exp")
        
        var success = true
        let uuid = UUID()
        
        api.addUser(cloudFolderName: cloudFolderName, emailAddress: emailAddress, sharingGroupUUID: uuid, sharingGroupName: nil) { result in
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
    private func removeUser() -> Bool {
        let exp = expectation(description: "exp")
        
        var success = true
        
        api.removeUser { error in
            success = error == nil
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        
        return success
    }

    // 4/10/21: I'm getting `tooManyRequests` errors from Dropbox: Could not uploadFile: error: badStatusCode(Optional(KituraNet.HTTPStatusCode.tooManyRequests))
    // And response headers have: [2021-04-11T03:33:37.031Z] [DEBUG] [DropboxCreds+CloudStorage.swift:48 logHeaders(responseHeaders:)] header: (key: "Retry-After", value: ["15"])
    // See also https://developers.dropbox.com/error-handling-guide
    // https://stackoverflow.com/questions/67047856
    private func createDropboxCredentials(selectUser: SelectUser = .first) throws -> GenericCredentials {
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
    
    private func createGoogleCredentials() throws -> GenericCredentials {
        let keyData = try Data(contentsOf: googleKeyURL)
        let key = try JSONDecoder().decode(GoogleKey.self, from: keyData)
        
        // This does necessary initializations for Google-- so that token can be refreshed.
        // Have to futz around here. Can only call this once.
        if !calledGoogleSetup {
            _ = GoogleSyncServerSignIn(serverClientId: key.GoogleServerClientId, appClientId: key.GoogleClientId, signInDelegate: self)
            calledGoogleSetup = true
        }
        
        let googleCredentials = URL(fileURLWithPath: googleCredentialsPath)

        let savedCreds = try GoogleSavedCreds.fromJSON(file: googleCredentials)
        
        let creds = GoogleCredentials(savedCreds: savedCreds)

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
            removeUser: removeUser,
            addUser: addUser
        )
    }

    func googleUser() throws -> TestUser {
        let creds = try createGoogleCredentials()
        return TestUser(
            cloudStorageType: .Google,
            credentials:creds,
            hashing: GoogleHashing(),
            removeUser: removeUser,
            addUser: addUser
        )
    }
    
    // MARK: GoogleSignInDelegate
    func getCurrentViewController() -> UIViewController? {
        return nil
    }
}

