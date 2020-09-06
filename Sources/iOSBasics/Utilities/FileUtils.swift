//
//  FileUtils.swift
//  
//
//  Created by Christopher G Prince on 9/5/20.
//

import Foundation
import iOSShared

struct FileUtils {
    // Returns the URL to the copy
    static func copyFileToNewTemporary(original: URL, config: Networking.Configuration) throws -> URL {
        try Files.createDirectoryIfNeeded(config.temporaryFileDirectory)
        let tempFile = try Files.createTemporary(withPrefix: config.temporaryFilePrefix, andExtension: config.temporaryFileExtension, inDirectory: config.temporaryFileDirectory)
        try? FileManager.default.removeItem(at: tempFile)
        try FileManager.default.copyItem(at: original, to: tempFile)
        return tempFile
    }
}
