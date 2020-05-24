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

class NetworkingTests: XCTestCase, Dropbox, ServerBasics {
    var networking: Networking!
    var credentials: GenericCredentials!
    var savedCredentials: DropboxSavedCreds!
    let hashing = DropboxHashing()
    let deviceUUID = UUID()
    var database:Connection!
    let config = Networking.Configuration(temporaryFileDirectory: Files.getDocumentsDirectory(), temporaryFilePrefix: "SyncServer", temporaryFileExtension: "dat", baseURL: baseURL(), minimumServerVersion: nil, packageTests: true)
    
    override func setUpWithError() throws {
        database = try Connection(.inMemory)
        savedCredentials = try loadDropboxCredentials()
        credentials = DropboxCredentials(savedCreds:savedCredentials)
        networking = Networking(database: database, delegate: self, config: config)
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
        
        let configuration = Networking.RequestConfiguration(credentials: credentials)

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

extension NetworkingTests: ServerAPIDelegate {
    func downloadCompleted(_ api: AnyObject, result: Swift.Result<UploadFileResult, Error>) {
        assert(false)
    }
    
    func downloadError(_ api: AnyObject, error: Error) {
        assert(false)
    }
    
    func uploadError(_ api: AnyObject, error: Error) {
        assert(false)
    }
    
    func uploadCompleted(_ api: AnyObject, result: Swift.Result<UploadFileResult, Error>) {
        assert(false)
    }
    
    func currentHasher(_ api: AnyObject) -> CloudStorageHashing {
        return hashing
    }
    
    func credentialsForNetworkRequests(_ api: AnyObject) -> GenericCredentials {
        return credentials
    }
    
    func deviceUUID(_ api: AnyObject) -> UUID {
        return deviceUUID
    }
}
