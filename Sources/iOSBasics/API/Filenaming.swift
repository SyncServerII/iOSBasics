//
//  Filenaming.swift
//  
//
//  Created by Christopher G Prince on 8/23/20.
//

import Foundation
import ServerShared

protocol Filenaming {
    var fileUUID: String! {get}
    var fileVersion: FileVersionInt! {get}
    
    // id field of a DownloadObjectTracker
    var trackerId: Int64 {get}
}

struct FileObject: Filenaming {
    let fileUUID: String!
    let fileVersion: FileVersionInt!
    
    // A SQLLite id for the tracker object. i.e., for the DownloadObjectTracker
    let trackerId: Int64
}
