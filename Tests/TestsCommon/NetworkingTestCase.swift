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
import Version

protocol ServerAPIDelegator: ServerAPIDelegate {
    var handlers: DelegateHandlers {get}
    var deviceUUID: UUID! {get}
    var hashingManager: HashingManager! {get}
}

extension ServerAPIDelegator {
    func badVersion(_ delegated: AnyObject, version: BadVersion) {
        XCTFail()
    }
    
    func error(_ delegated: AnyObject, error: Error?) {
        XCTFail("\(String(describing: error))")
    }
    
    func downloadCompleted(_ delegated: AnyObject, result: Swift.Result<DownloadFileResult, Error>) {
        handlers.api.downloadCompletedHandler?(result)
    }
    
    func uploadCompleted(_ delegated: AnyObject, file: Filenaming, result: Swift.Result<UploadFileResult, Error>) {
         handlers.api.uploadCompletedHandler?(result)
    }
    
    func backgroundRequestCompleted(_ delegated: AnyObject, result: Swift.Result<BackgroundRequestResult, Error>) {
        handlers.api.backgroundRequestCompletedHandler?(result)
    }
    
    func hasher(_ delegated: AnyObject, forCloudStorageType cloudStorageType: CloudStorageType) throws -> CloudStorageHashing {
        return try hashingManager.hashFor(cloudStorageType: cloudStorageType)
    }
    
    func credentialsForNetworkRequests(_ delegated: AnyObject) throws -> GenericCredentials {
        return handlers.user.credentials
    }
    
    func deviceUUID(_ delegated: AnyObject) -> UUID {
        return deviceUUID
    }
}
