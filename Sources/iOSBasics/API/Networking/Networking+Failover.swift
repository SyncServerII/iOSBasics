//
//  Networking+Failover.swift
//  
//
//  Created by Christopher G Prince on 4/10/21.
//

import Foundation

extension Networking {
    private func getFailoverMessage(completion: @escaping (_ message: String?)->()) {
        guard let failoverURL = config.failoverMessageURL else {
            completion(nil)
            return
        }
        
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config)
        let task = session.downloadTask(with: failoverURL) { url, urlResponse, error in
            guard let url = url, error == nil,
                let data = try? Data(contentsOf: url),
                let string = String(data: data, encoding: .utf8) else {
                completion(nil)
                return
            }
            
            completion(string)
        }
        
        task.resume()
    }
    
    // Call this if you get a serviceUnavailable HTTP response. This calls the networkingFailover delegate method if it could obtain a failover message.
    func failover(completion: @escaping ()->()) {
        getFailoverMessage() { [weak self] message in
            guard let self = self else { return }
            if let message = message {
                self.delegate.networkingFailover(self, message: message)
            }
            
            completion()
        }
    }
}
