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
}

struct FileObject: Filenaming {
    let fileUUID: String!
    let fileVersion: FileVersionInt!
}
