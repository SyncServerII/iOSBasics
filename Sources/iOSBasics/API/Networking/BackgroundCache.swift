import Foundation
import SQLite
import iOSShared
import ServerShared

// For caching the results of downloading and uploading files using a background URLSession.

class BackgroundCache {
    enum BackgroundCacheError: Error {
        case couldNotLookup
        case wrongTransferType
        case badUUID
    }
    
    let database: Connection
    
    init(database: Connection) {
        self.database = database
    }
    
    func initializeUploadCache(fileUUID:String, uploadObjectTrackerId: Int64, taskIdentifer: Int) throws {
        guard let uuid = UUID(uuidString: fileUUID) else {
            throw BackgroundCacheError.badUUID
        }
        
        let cache = try NetworkCache(db: database, taskIdentifier: taskIdentifer, uuid: uuid, trackerId: uploadObjectTrackerId, fileVersion: nil, transfer: .upload(nil))
        try cache.insert()
    }
    
    func initializeDownloadCache(file:Filenaming,
        taskIdentifer: Int) throws {
        guard let uuid = UUID(uuidString: file.fileUUID) else {
            throw BackgroundCacheError.badUUID
        }
        
        let cache = try NetworkCache(db: database, taskIdentifier: taskIdentifer, uuid: uuid, trackerId: file.trackerId, fileVersion: file.fileVersion, transfer: .download(nil))
        try cache.insert()
    }
    
    func initializeRequestCache(uuid:String, trackerId: Int64, taskIdentifer: Int, requestInfo: Data?) throws {
        guard let uuid = UUID(uuidString: uuid) else {
            throw BackgroundCacheError.badUUID
        }
        
        let cache = try NetworkCache(db: database, taskIdentifier: taskIdentifer, uuid: uuid, trackerId: trackerId, fileVersion: nil, transfer: .request(nil), requestInfo: requestInfo)
        try cache.insert()
    }
    
    func lookupCache(taskIdentifer: Int) throws -> NetworkCache {
        guard let cache = try NetworkCache.fetchSingleRow(db: database,
            where: taskIdentifer == NetworkCache.taskIdentifierField.description) else {
            throw NetworkingError.couldNotGetCache
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
    
    func cacheRequestResult(taskIdentifer: Int, response:HTTPURLResponse, localURL: URL) throws {
    
        guard let cache = try NetworkCache.fetchSingleRow(db: database, where: taskIdentifer == NetworkCache.taskIdentifierField.description) else {
            throw BackgroundCacheError.couldNotLookup
        }
        
        guard case .request = cache.transfer else {
            throw BackgroundCacheError.wrongTransferType
        }
        
        let download = NetworkTransfer.request(localURL)
        
        try cache.update(setters:
            NetworkCache.transferField.description <- download
        )
    }
}
