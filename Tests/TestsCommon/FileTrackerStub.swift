//
//  FileTrackerStub.swift
//  
//
//  Created by Christopher G Prince on 8/8/21.
//

import Foundation
@testable import iOSBasics

public struct FileTrackerStub: BackgroundCacheFileTracker {
    public var networkCacheId: Int64?
    public func update(networkCacheId: Int64) throws {
    }
}
