//
//  NetworkingTests.swift
//  iOSBasicsTests
//
//  Created by Christopher G Prince on 5/17/20.
//

import XCTest
@testable import iOSBasics
@testable import iOSDropbox
import iOSSignIn
import iOSShared
import ServerShared
import SQLite

class NetworkingTests: XCTestCase, UserSetup, ServerBasics, ServerAPIDelegator {
    var deviceUUID: UUID!
    var hashingManager: HashingManager!
    var uploadCompletedHandler: ((Swift.Result<UploadFileResult, Error>) -> ())?
    var downloadCompletedHandler: ((Swift.Result<DownloadFileResult, Error>) -> ())?
    var api: ServerAPI!
    var networking: Networking!
    let handlers = DelegateHandlers()
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        deviceUUID = UUID()
        let database = try Connection(.inMemory)
        let config = Configuration(appGroupIdentifier: nil, sqliteDatabasePath: "", serverURL: URL(string: Self.baseURL())!, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true)
        networking = Networking(database: database, delegate: self, config: config)
        hashingManager = HashingManager()
        try? hashingManager.add(hashing: DropboxHashing())
        api = ServerAPI(database: database, hashingManager: hashingManager, delegate: self, config: config)
        handlers.user = try dropboxUser()
    }

    override func tearDownWithError() throws {
    }

    func testNetworkingRequestWithNoCredentials() throws {
        let endpoint = ServerEndpoints.healthCheck
        let serverURL = ServerAPI.makeURL(forEndpoint: endpoint, baseURL: Self.baseURL())
        
        let exp = expectation(description: "exp")
        
        networking.sendRequestTo(serverURL, method: endpoint.method) { (response, httpCode, error) in
            // Check one of the response keys in the health check
            XCTAssert(response?["deployedGitTag"] != nil)
            
            XCTAssert(error == nil)
            XCTAssert(httpCode == HTTPStatus.ok.rawValue)
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testNetworkingRequestWithCredentials() throws {
        let endpoint = ServerEndpoints.checkCreds
        let serverURL = ServerAPI.makeURL(forEndpoint: endpoint, baseURL: Self.baseURL())
        
        let exp = expectation(description: "exp")
        
        let configuration = Networking.RequestConfiguration(credentials: handlers.user.credentials)

        networking.sendRequestTo(serverURL, method: endpoint.method, configuration: configuration) { response, httpStatus, error in

            if httpStatus == HTTPStatus.unauthorized.rawValue {
            }
            else if httpStatus == HTTPStatus.ok.rawValue {
            }
            else {
                XCTFail()
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
}
