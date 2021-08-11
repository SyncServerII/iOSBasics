//
//  URL+Extras.swift
//  
//
//  Created by Christopher G Prince on 8/10/21.
//

import Foundation
import iOSShared

extension URL {
    func canReadFile() -> Bool {
        guard let fileHandle = FileHandle(forReadingAtPath: path) else {
            return false
        }
        
        do {
            try fileHandle.close()
        } catch let error {
            logger.error("canReadFile: \(error)")
            return false
        }
        
        return true
    }
}
