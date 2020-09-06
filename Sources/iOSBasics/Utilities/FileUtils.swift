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
    static func copyFileToNewTemporary(original: URL, config: Configuration.TemporaryFiles) throws -> URL {
        try Files.createDirectoryIfNeeded(config.directory)
        let tempFile = try Files.createTemporary(withPrefix: config.filePrefix, andExtension: config.fileExtension, inDirectory: config.directory)
        try? FileManager.default.removeItem(at: tempFile)
        try FileManager.default.copyItem(at: original, to: tempFile)
        return tempFile
    }
    
    static func copyDataToNewTemporary(data: Data, config: Configuration.TemporaryFiles) throws -> URL {
        try Files.createDirectoryIfNeeded(config.directory)
        let tempFile = try Files.createTemporary(withPrefix: config.filePrefix, andExtension: config.fileExtension, inDirectory: config.directory)
        try? FileManager.default.removeItem(at: tempFile)
        try data.write(to: tempFile)
        return tempFile
    }
}
