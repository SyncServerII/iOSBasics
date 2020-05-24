import Foundation
import SQLite
import iOSShared
import ServerShared

// For caching the results of downloading and uploading files using a background URLSession.

class BackgroundCache {
    enum BackgroundCacheError: Error {
        case couldNotLookup
        case wrongTransferType
    }
    
    let database: Connection
    
    init(database: Connection) {
        self.database = database
    }
    
    func initializeUploadCache(file:Filenaming, taskIdentifer: Int) throws {
        let cache = try NetworkCache(db: database, taskIdentifier: taskIdentifer, fileUUID: file.fileUUID, fileVersion: file.fileVersion, transfer: .upload(nil))
        try cache.insert()
    }
    
    func initializeDownloadCache(file:FilenamingWithAppMetaDataVersion,
        taskIdentifer: Int) throws {
        let cache = try NetworkCache(db: database, taskIdentifier: taskIdentifer, fileUUID: file.fileUUID, fileVersion: file.fileVersion, transfer: .download(nil), appMetaDataVersion: file.appMetaDataVersion)
        try cache.insert()
    }
    
    func lookupCache(taskIdentifer: Int) throws -> NetworkCache? {
        guard let cache = try NetworkCache.fetchSingleRow(db: database,
            where: taskIdentifer == NetworkCache.taskIdentifierField.description) else {
            return nil
        }
        
        return cache
    }
    
    func cacheUploadResult(taskIdentifer: Int, uploadBody: [String: Any]) throws {
        guard let cache = try NetworkCache.fetchSingleRow(db: database, where: taskIdentifer == NetworkCache.taskIdentifierField.description) else {
            throw BackgroundCacheError.couldNotLookup
        }
        
        guard case .upload = cache.transfer else {
            throw BackgroundCacheError.wrongTransferType
        }

        let upload = NetworkTransfer.upload(UploadBody(dictionary: uploadBody))
        
        try cache.update(setters:
            NetworkCache.transferField.description <- upload
        )
    }
    
    func cacheDownloadResult(taskIdentifer: Int, response:HTTPURLResponse, localURL: URL) throws {
    
        guard let cache = try NetworkCache.fetchSingleRow(db: database, where: taskIdentifer == NetworkCache.taskIdentifierField.description) else {
            throw BackgroundCacheError.couldNotLookup
        }
        
        guard case .download = cache.transfer else {
            throw BackgroundCacheError.wrongTransferType
        }
        
        let download = NetworkTransfer.download(localURL)
        
        try cache.update(setters:
            NetworkCache.transferField.description <- download
        )
    }
    
    // If the NetworkCache object is returned, it has been removed from the database.
    func lookupAndRemoveCache(file:Filenaming, download: Bool) throws -> NetworkCache? {
        guard let cache = try NetworkCache.fetchSingleRow(db: database, where: file.fileUUID == NetworkCache.fileUUIDField.description &&
            file.fileVersion == NetworkCache.fileVersionField.description) else {
            throw BackgroundCacheError.couldNotLookup
        }
        
        guard let transfer = cache.transfer else {
            logger.warning("transfer field of cache was nil")
            return nil
        }
        
        switch transfer {
        case .upload:
            if download {
                return nil
            }
            else {
                try cache.delete()
                return cache
            }
            
        case .download:
            if download {
                try cache.delete()
                return cache
            }
            else {
                return nil
            }
        }
    }
    
    func lookupAndRemoveCache(taskIdentifer: Int) throws -> NetworkCache? {
        guard let cache = try NetworkCache.fetchSingleRow(db: database,
            where: taskIdentifer == NetworkCache.taskIdentifierField.description) else {
            return nil
        }
        
        try cache.delete()
        return cache
    }
    
    func removeCache(taskIdentifer: Int) throws {
        guard let cache = try NetworkCache.fetchSingleRow(db: database, where: taskIdentifer == NetworkCache.taskIdentifierField.description) else {
            throw BackgroundCacheError.couldNotLookup
        }
        
        try cache.delete()
    }
}
