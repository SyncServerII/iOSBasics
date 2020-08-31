//
//  NetworkingTestCase.swift
//  
//
//  Created by Christopher G Prince on 8/30/20.
//

import Foundation
import XCTest
@testable import iOSBasics
import iOSSignIn
import iOSShared
import ServerShared
import SQLite

protocol NetworkingProtocol: AnyObject {
    var serverCredentials: ServerCredentials! {get set}
    var uploadCompletedHandler: ((_ result: Swift.Result<UploadFileResult, Error>) -> ())? {get set}
    var downloadCompletedHandler: ((_ result: Swift.Result<DownloadFileResult, Error>) -> ())? {get set}
}

struct ServerCredentials {
    let credentials: GenericCredentials
    let hashing: CloudStorageHashing
}

class NetworkingTestCase: XCTestCase, ServerBasics, NetworkingProtocol {
    var database:Connection!
    var networking: Networking!
    var deviceUUID = UUID()
    
    var serverCredentials: ServerCredentials!
    var uploadCompletedHandler: ((_ result: Swift.Result<UploadFileResult, Error>) -> ())?
    var downloadCompletedHandler: ((_ result: Swift.Result<DownloadFileResult, Error>) -> ())?

    let config = Networking.Configuration(temporaryFileDirectory: Files.getDocumentsDirectory(), temporaryFilePrefix: "SyncServer", temporaryFileExtension: "dat", baseURL: baseURL(), minimumServerVersion: nil, packageTests: true)

    override func setUpWithError() throws {
        database = try Connection(.inMemory)
        networking = Networking(database: database, delegate: self, config: config)
    }

    override func tearDownWithError() throws {
    }
}

extension NetworkingTestCase: ServerAPIDelegate {
    func downloadCompleted(_ api: AnyObject, result: Swift.Result<DownloadFileResult, Error>) {
        downloadCompletedHandler?(result)
    }
    
    func uploadCompleted(_ api: AnyObject, result: Swift.Result<UploadFileResult, Error>) {
        uploadCompletedHandler?(result)
    }
    
    func hasher(_ api: AnyObject, forCloudStorageType cloudStorageType: CloudStorageType) throws -> CloudStorageHashing {
        return serverCredentials.hashing
    }
    
    func credentialsForNetworkRequests(_ api: AnyObject) -> GenericCredentials {
        return serverCredentials.credentials
    }
    
    func deviceUUID(_ api: AnyObject) -> UUID {
        return deviceUUID
    }
}
