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
import iOSDropbox

protocol NetworkingProtocol: AnyObject {
    var credentials: GenericCredentials! {get set}
    var uploadCompletedHandler: ((_ result: Swift.Result<UploadFileResult, Error>) -> ())? {get set}
    var downloadCompletedHandler: ((_ result: Swift.Result<DownloadFileResult, Error>) -> ())? {get set}
}

class NetworkingTestCase: XCTestCase, ServerBasics, NetworkingProtocol {
    let hashingManager = HashingManager()
    var deviceUUID = UUID()
    var database:Connection!
    var networking: Networking!
    var api:ServerAPI!
    
    var credentials: GenericCredentials!
    var uploadCompletedHandler: ((_ result: Swift.Result<UploadFileResult, Error>) -> ())?
    var downloadCompletedHandler: ((_ result: Swift.Result<DownloadFileResult, Error>) -> ())?

    let config = Networking.Configuration(temporaryFileDirectory: Files.getDocumentsDirectory(), temporaryFilePrefix: "SyncServer", temporaryFileExtension: "dat", baseURL: baseURL(), minimumServerVersion: nil, packageTests: true)

    override func setUpWithError() throws {
        try super.setUpWithError()
        database = try Connection(.inMemory)
        networking = Networking(database: database, delegate: self, config: config)
        try? hashingManager.add(hashing: DropboxHashing())
        api = ServerAPI(database: database, hashingManager: hashingManager, delegate: self, config: config)
    }

    override func tearDownWithError() throws {
    }
}

extension NetworkingTestCase: ServerAPIDelegate {
    func downloadCompleted(_ delegated: AnyObject, result: Swift.Result<DownloadFileResult, Error>) {
        downloadCompletedHandler?(result)
    }
    
    func uploadCompleted(_ delegated: AnyObject, result: Swift.Result<UploadFileResult, Error>) {
        uploadCompletedHandler?(result)
    }
    
    func hasher(_ delegated: AnyObject, forCloudStorageType cloudStorageType: CloudStorageType) throws -> CloudStorageHashing {
        return try hashingManager.hashFor(cloudStorageType: cloudStorageType)
    }
    
    func credentialsForNetworkRequests(_ delegated: AnyObject) -> GenericCredentials {
        return credentials
    }
    
    func deviceUUID(_ delegated: AnyObject) -> UUID {
        return deviceUUID
    }
}
