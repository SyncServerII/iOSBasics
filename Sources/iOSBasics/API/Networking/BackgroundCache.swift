import Foundation
import SQLite
import iOSShared
import ServerShared

// For caching the results of downloading and uploading files using a background URLSession.

// So we don't have to expose UploadFileTracker down into the API layer. This makes it easier for testing. Plus, the `UploadFileTracker` is a higher level structure, above the API.
protocol BackgroundCacheFileTracker {
    var networkCacheId: Int64? { get }
    func update(networkCacheId: Int64) throws
}

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
    
    func initializeUploadCache(fileTracker: BackgroundCacheFileTracker, fileUUID:String, uploadObjectTrackerId: Int64, taskIdentifer: Int) throws {
        guard let fileUUID = UUID(uuidString: fileUUID) else {
            throw BackgroundCacheError.badUUID
        }

        if let priorNetworkCacheId = fileTracker.networkCacheId {
            let priorCache = try NetworkCache.fetchSingleRow(db: database, where: NetworkCache.idField.description == priorNetworkCacheId)
            try priorCache?.delete()
        }

        let cache = try NetworkCache(db: database, taskIdentifier: taskIdentifer, uuid: fileUUID, trackerId: uploadObjectTrackerId, fileVersion: nil, transfer: .upload(nil))
        try cache.insert()
        
        try fileTracker.update(networkCacheId: cache.id)
    }
    
    func initializeDownloadCache(file:Filenaming,
        taskIdentifer: Int) throws {
        guard let uuid = UUID(uuidString: file.fileUUID) else {
            throw BackgroundCacheError.badUUID
        }
        
        let cache = try NetworkCache(db: database, taskIdentifier: taskIdentifer, uuid: uuid, trackerId: file.trackerId, fileVersion: file.fileVersion, transfer: .download(nil))
        try cache.insert()
    }
    
    func initializeRequestCache(fileTracker: BackgroundCacheFileTracker, uuid:String, trackerId: Int64, taskIdentifer: Int, requestInfo: Data?) throws {
        guard let uuid = UUID(uuidString: uuid) else {
            throw BackgroundCacheError.badUUID
        }

        if let priorNetworkCacheId = fileTracker.networkCacheId {
            let priorCache = try NetworkCache.fetchSingleRow(db: database, where: NetworkCache.idField.description == priorNetworkCacheId)
            try priorCache?.delete()
        }
        
        let cache = try NetworkCache(db: database, taskIdentifier: taskIdentifer, uuid: uuid, trackerId: trackerId, fileVersion: nil, transfer: .request(nil), requestInfo: requestInfo)
        try cache.insert()
        
        try fileTracker.update(networkCacheId: cache.id)
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
