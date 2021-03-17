//
//  FakeRequestable.swift
//  
//
//  Created by Christopher G Prince on 2/21/21.
//

import Foundation
import iOSShared

class FakeRequestable: NetworkRequestable {
    var canMakeNetworkRequests: Bool {
        return true
    }
}
