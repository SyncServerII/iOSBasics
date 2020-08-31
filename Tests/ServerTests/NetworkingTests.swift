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

class NetworkingTests: NetworkingTestCase, Dropbox {
    override func setUpWithError() throws {
        try super.setUpWithError()
        serverCredentials = try createDropboxCredentials()
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
        
        let configuration = Networking.RequestConfiguration(credentials: serverCredentials.credentials)

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
