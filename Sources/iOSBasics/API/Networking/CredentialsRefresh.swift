//
//  CredentialsRefresh.swift
//  
//
//  Created by Christopher G Prince on 6/16/21.
//

import Foundation
import iOSSignIn
import ServerShared
import iOSShared

// Carry out a credentials refresh if needed while performing a basic network request. Not intended for background URL session network requests.
// See https://github.com/SyncServerII/Neebla/issues/17

protocol CredentialsRefreshDelegate: AnyObject {
    func cache(refresh: CredentialsRefresh)
    func removeFromCache(refresh: CredentialsRefresh)
}

class CredentialsRefresh: Hashable {
    let id:Int64
    private static var nextId: Int64 = 0

    var networkRequest: ((_ headers: [String:String])->())!
    
    private let credentials:() throws -> (Networking.Authentication)
    private var refreshDone = false
    weak var delegate: CredentialsRefreshDelegate?
    private var authentication: Networking.Authentication!
    
    // `credentials` is called once before any refresh, and after a refresh if it is needed and if it is successful.
    init(delegate: CredentialsRefreshDelegate, credentials: @escaping () throws ->(Networking.Authentication)) throws {
        self.credentials = credentials
        id = Self.nextId
        Self.nextId += 1
        self.delegate = delegate
        self.authentication = try credentials()
    }
    
    deinit {
        logger.info("deinit: CredentialsRefresh")
    }
    
    // If the status code indicates, do a credentials refresh a single time.
    // Otherwise, call the completion.
    func checkResponse(statusCode:Int?, completion: @escaping (Error?)->()) {
        logger.notice("CredentialsRefresh: statusCode: \(String(describing: statusCode)); refreshDone: \(refreshDone)")

        if statusCode == HTTPStatus.unauthorized.rawValue, !refreshDone {
            refreshDone = true
            
            logger.notice("CredentialsRefresh: got .unauthorized; attempting refresh.")
            
            // The critical steps:
            
            // 1) Refresh credentials
            self.authentication.credentials.refreshCredentials { [weak self] error in
                guard let self = self else {
                    logger.error("CredentialsRefresh: No self!")
                    completion(NetworkingError.noSelf)
                    return
                }
                
                if let error = error {
                    logger.error("CredentialsRefresh: error on refresh: \(error)")
                    completion(error)
                    return
                }
                
                logger.notice("CredentialsRefresh: Successs!")
                
                // 2) Get the new credentials, after the successful refresh.
                do {
                    self.authentication = try self.credentials()
                } catch let error {
                    completion(error)
                    return
                }

                // 3) Use those credentials to form the headers for the request retry
                self.networkRequest?(self.authentication.headers)
            }
        }
        else {
            completion(nil)
            delegate?.removeFromCache(refresh: self)
        }
    }
    
    func start() {
        guard let authentication = authentication else {
            logger.error("Could not get authentication")
            return
        }
        
        delegate?.cache(refresh: self)
        networkRequest?(authentication.headers)
    }
    
    // MARK: Hashable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: CredentialsRefresh, rhs: CredentialsRefresh) -> Bool {
        lhs.id == rhs.id
    }
}
