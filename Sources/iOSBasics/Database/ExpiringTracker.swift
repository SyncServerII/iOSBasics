//
//  ExpiringTracker.swift
//  
//
//  Created by Christopher G Prince on 8/15/21.
//

import Foundation

protocol ExpiringTracker {
    var expiry: Date? { get }
}

enum ExpiringTrackerError: Error {
    case couldNotCreateExpiry
    case noExpiryDate
}
    
extension ExpiringTracker {
    static func expiryDate(expiryDuration: TimeInterval) throws -> Date {
        let calendar = Calendar.current
        guard let expiryDate = calendar.date(byAdding: .second, value: Int(expiryDuration), to: Date()) else {
            throw ExpiringTrackerError.couldNotCreateExpiry
        }
        
        return expiryDate
    }
    
    // Has the `expiry` Date of the tracker expired? Assumes that this tracker has a non-nil `expiry` and throws an error if the `expiry` Date is nil.
    func hasExpired() throws -> Bool {
        guard let expiry = expiry else {
            throw ExpiringTrackerError.noExpiryDate
        }
        
        return expiry <= Date()
    }
}
