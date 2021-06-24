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
    
    var networkRequest: (()->())!
    private var refreshDone = false
    private let credentials: GenericCredentials
    weak var delegate: CredentialsRefreshDelegate?
    
    init(credentials: GenericCredentials, delegate: CredentialsRefreshDelegate) {
        self.credentials = credentials
        id = Self.nextId
        Self.nextId += 1
        self.delegate = delegate
    }
    
    deinit {
        // logger.info("deinit: CredentialsRefresh")
    }
    
    // If the status code indicates, do a credentials refresh a single time.
    // Otherwise, call the completion.
    func checkResponse(statusCode:Int?, completion: @escaping (Error?)->()) {
        logger.notice("CredentialsRefresh: statusCode: \(String(describing: statusCode)); refreshDone: \(refreshDone)")

        if statusCode == HTTPStatus.unauthorized.rawValue, !refreshDone {
            refreshDone = true
            
            logger.notice("CredentialsRefresh: got .unauthorized; attempting refresh.")
            
            credentials.refreshCredentials { [weak self] error in
                guard let self = self else {
                    logger.error("CredentialsRefresh: No self!")
                    return
                }
                
                if let error = error {
                    logger.error("CredentialsRefresh: error on refresh: \(error)")
                    completion(error)
                    return
                }
                
                logger.notice("CredentialsRefresh: Successs!")

                self.networkRequest?()
            }
        }
        else {
            completion(nil)
            delegate?.removeFromCache(refresh: self)
        }
    }
    
    func start() {
        delegate?.cache(refresh: self)
        networkRequest?()
    }
    
    // MARK: Hashable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: CredentialsRefresh, rhs: CredentialsRefresh) -> Bool {
        lhs.id == rhs.id
    }
}
