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
@testable import TestsCommon

class NetworkingTests: XCTestCase, UserSetup, ServerBasics, ServerAPIDelegator {
    var deviceUUID: UUID!
    var hashingManager: HashingManager!
    var api: ServerAPI!
    var networking: Networking!
    let handlers = DelegateHandlers()
    var backgroundRequestCompleted: ((_ network: Any, URL?, _ trackerId:Int64, HTTPURLResponse?, _ requestInfo: Data?, _ statusCode:Int?) -> ())?
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        deviceUUID = UUID()
        let database = try Connection(.inMemory)
        let config = Configuration(appGroupIdentifier: nil, serverURL: URL(string: Self.baseURL())!, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true)
        networking = Networking(database: database, delegate: self, transferDelegate: self, config: config)
        hashingManager = HashingManager()
        try? hashingManager.add(hashing: DropboxHashing())
        api = ServerAPI(database: database, hashingManager: hashingManager, delegate: self, config: config)
        handlers.user = try dropboxUser()
        _ = handlers.user.removeUser()
        XCTAssert(handlers.user.addUser())
        try NetworkCache.createTable(db: database)
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
    
    func testBackgroundRequest() throws {
        let endpoint = ServerEndpoints.checkCreds
        let serverURL = ServerAPI.makeURL(forEndpoint: endpoint, baseURL: Self.baseURL())
        
        let trackerId:Int64 = 22
        let testString = "Hello, There!"
        
        guard let requestInfoData = testString.data(using: .utf8) else {
            XCTFail()
            return
        }
        
        var resultURL: URL?
        var requestInfo: Data?
        
        let exp = expectation(description: "exp")
        backgroundRequestCompleted = { _, url, id, _, info, statusCode in
            resultURL = url
            requestInfo = info
            XCTAssert(trackerId == id)
            XCTAssert(statusCode == 200)
            exp.fulfill()
        }
        
        let error = networking.sendBackgroundRequestTo(serverURL, method: endpoint.method, uuid: UUID(), trackerId: trackerId, requestInfo: requestInfoData)
        waitForExpectations(timeout: 10, handler: nil)
        
        guard error == nil else {
            XCTFail("\(String(describing: error))")
            return
        }
        
        guard let url = resultURL else {
            XCTFail()
            return
        }
        
        let data = try Data(contentsOf: url)

        let json = try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions(rawValue: UInt(0)))
                
        guard let jsonDict = json as? [String: Any] else {
            XCTFail()
            return
        }
                
        let response = try CheckCredsResponse.decode(jsonDict)
        XCTAssert(response.userId != nil)
        
        guard let info = requestInfo else {
            XCTFail()
            return
        }
        
        guard let infoString = String(data: info, encoding: .utf8) else {
            XCTFail()
            return
        }
        
        XCTAssert(infoString == testString)
    }
}

extension NetworkingTests: FileTransferDelegate {
    func error(_ network: Any, file: Filenaming?, statusCode:Int?, error:Error?) {
        XCTFail()
    }

    func downloadCompleted(_ network: Any, file: Filenaming, url: URL?, response: HTTPURLResponse?, _ statusCode:Int?) {
        XCTFail()
    }
    
    func uploadCompleted(_ network: Any, file: Filenaming, response: HTTPURLResponse?, responseBody: [String: Any]?, statusCode:Int?) {
        XCTFail()
    }
    
    func backgroundRequestCompleted(_ network: Any, url: URL?, trackerId: Int64, response: HTTPURLResponse?, requestInfo: Data?, statusCode: Int?) {
        backgroundRequestCompleted?(network, url, trackerId, response, requestInfo, statusCode)
    }
}
