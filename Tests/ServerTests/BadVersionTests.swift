//
//  BadVersionTests.swift
//  ServerTests
//
//  Created by Christopher G Prince on 4/10/21.
//

import XCTest
@testable import iOSBasics
@testable import iOSDropbox
import iOSSignIn
import iOSShared
import ServerShared
import SQLite
@testable import TestsCommon
import Version

class BadVersionTests: XCTestCase, UserSetup, ServerBasics, ServerAPIDelegator {
    var deviceUUID: UUID!
    var hashingManager: HashingManager!
    var api: ServerAPI!
    var networking: Networking!
    let handlers = DelegateHandlers()
    var backgroundRequestCompleted: ((_ network: Any, URL?, _ trackerId:Int64, HTTPURLResponse?, _ requestInfo: Data?, _ statusCode:Int?) -> ())?
        let serialQueue = DispatchQueue(label: "iOSBasicsTests")
    var database:Connection!
    var backgroundAssertable:BackgroundAsssertable!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        deviceUUID = UUID()
        hashingManager = HashingManager()
        try? hashingManager.add(hashing: DropboxHashing())
        database = try Connection(.inMemory)
        backgroundAssertable = MainAppBackgroundTask()
        
        try setup()
        
        handlers.user = try dropboxUser()
        _ = handlers.user.removeUser()
        XCTAssert(handlers.user.addUser())
        try NetworkCache.createTable(db: database)
        handlers.api.badVersion = nil
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func setup(minServerVersion: Version? = nil, clientAppVersion: Version? = nil) throws {
        let config = Configuration(appGroupIdentifier: nil, serverURL: URL(string: Self.baseURL())!, minimumServerVersion: minServerVersion, currentClientAppVersion: clientAppVersion, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true, deferredCheckInterval: nil)
        networking = Networking(database: database, serialQueue: serialQueue, backgroundAsssertable: backgroundAssertable, delegate: self, transferDelegate: self, config: config)
        api = ServerAPI(database: database, hashingManager: hashingManager, delegate: self, serialQueue: serialQueue, backgroundAsssertable: backgroundAssertable, config: config)
    }
    
    func testBadServerVersion() throws {
        // Assume: actual server version is lower than this
        try setup(minServerVersion: Version("2.0.0"))
        
        var gotBadServerVersion = false
            
        handlers.api.badVersion = { _, badVersion in
            switch badVersion {
            case .badServerVersion:
                gotBadServerVersion = true
            case .badClientAppVersion:
                XCTFail()
            }
        }
        
        let exp = expectation(description: "exp")

        api.healthCheck { result in
            switch result {
            case .success:
                XCTFail()
                
            case .failure:
                XCTAssert(gotBadServerVersion)
            }
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testBadClientAppVersion() throws {
        // Assume: Min client version specified in server config is higher than this.
        try setup(clientAppVersion: Version("0.0.1"))
        
        var gotBadClientAppVersion = false
            
        handlers.api.badVersion = { _, badVersion in
            switch badVersion {
            case .badServerVersion:
                XCTFail()
            case .badClientAppVersion:
                gotBadClientAppVersion = true
            }
        }
        
        let exp = expectation(description: "exp")

        api.healthCheck { result in
            switch result {
            case .success:
                XCTFail()
                
            case .failure:
                XCTAssert(gotBadClientAppVersion)
            }
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)    
    }
}

extension BadVersionTests: FileTransferDelegate {
    func error(_ network: Any, file: Filenaming?, statusCode:Int?, error:Error?) {
        XCTFail()
    }

    func downloadCompleted(_ network: Any, file: Filenaming, event: FileTransferDownloadEvent, response: HTTPURLResponse?) {
        XCTFail()
    }
    
    func uploadCompleted(_ network: Any, file: Filenaming, event: FileTransferUploadEvent, response: HTTPURLResponse?) {
        XCTFail()
    }
    
    func backgroundRequestCompleted(_ network: Any, url: URL?, trackerId: Int64, response: HTTPURLResponse?, requestInfo: Data?, statusCode: Int?) {
        backgroundRequestCompleted?(network, url, trackerId, response, requestInfo, statusCode)
    }
}
