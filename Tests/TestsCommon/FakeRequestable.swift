//
//  FakeRequestable.swift
//  
//
//  Created by Christopher G Prince on 2/21/21.
//

import Foundation
import iOSShared

class FakeRequestable: NetworkRequestable {
    func canMakeNetworkRequests(options: NetworkRequestableOptions) -> Bool {
        true
    }
    
    var canMakeNetworkRequests: Bool {
        return true
    }
}
