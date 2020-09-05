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

protocol ServerAPIDelegator: ServerAPIDelegate {
    var user: TestUser! {get set}
    var deviceUUID: UUID! {get}
    var hashingManager: HashingManager! {get}
    var uploadCompletedHandler: ((_ result: Swift.Result<UploadFileResult, Error>) -> ())? {get set}
    var downloadCompletedHandler: ((_ result: Swift.Result<DownloadFileResult, Error>) -> ())? {get set}
}

extension ServerAPIDelegator {
    func error(_ delegated: AnyObject, error: Error?) {
        XCTFail("\(String(describing: error))")
    }
    
    func downloadCompleted(_ delegated: AnyObject, result: Swift.Result<DownloadFileResult, Error>) {
        downloadCompletedHandler?(result)
    }
    
    func uploadCompleted(_ delegated: AnyObject, result: Swift.Result<UploadFileResult, Error>) {
        uploadCompletedHandler?(result)
    }
    
    func hasher(_ delegated: AnyObject, forCloudStorageType cloudStorageType: CloudStorageType) throws -> CloudStorageHashing {
        return try hashingManager.hashFor(cloudStorageType: cloudStorageType)
    }
    
    func credentialsForNetworkRequests(_ delegated: AnyObject) throws -> GenericCredentials {
        return user.credentials
    }
    
    func deviceUUID(_ delegated: AnyObject) -> UUID {
        return deviceUUID
    }
}
