//
//  FakeReachability.swift
//  
//
//  Created by Christopher G Prince on 2/21/21.
//

import Foundation
import iOSShared

class FakeReachability: NetworkReachability {
    var isReachable: Bool {
        return true
    }
}
