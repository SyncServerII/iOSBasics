import XCTest
@testable import iOSBasics
import SQLite
import ServerShared

class BackgroundCacheTests: XCTestCase {
    var database: Connection!
    var entry:NetworkCache!
    var backgroundCache:BackgroundCache!
    let taskIdentifier = 1
    
    override func setUpWithError() throws {
        database = try Connection(.inMemory)
        backgroundCache = BackgroundCache(database: database)
        try NetworkCache.createTable(db: database)
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testInitializeUploadCache() throws {
        let file = FileObject(fileUUID: UUID().uuidString, fileVersion: 1)
        try backgroundCache.initializeUploadCache(file: file, taskIdentifer: taskIdentifier)
        
        guard let result = try NetworkCache.fetchSingleRow(db: database, where:
            taskIdentifier == NetworkCache.taskIdentifierField.description) else {
            XCTFail()
            return
        }
        
        XCTAssert(result.fileVersion == file.fileVersion)
        XCTAssert(result.fileUUID == file.fileUUID)
        XCTAssert(result.taskIdentifier == taskIdentifier)
        
        guard case .upload(let body) = result.transfer, body == nil else {
            XCTFail()
            return
        }
    }
    
    func testInitializeDownloadCache() throws {
        let file = FilenamingWithAppMetaDataVersion(fileUUID: UUID().uuidString, fileVersion: 1, appMetaDataVersion: nil)
        try backgroundCache.initializeDownloadCache(file: file, taskIdentifer: taskIdentifier)
        
        guard let result = try NetworkCache.fetchSingleRow(db: database, where:
            taskIdentifier == NetworkCache.taskIdentifierField.description) else {
            XCTFail()
            return
        }
        
        XCTAssert(result.fileVersion == file.fileVersion)
        XCTAssert(result.fileUUID == file.fileUUID)
        XCTAssert(result.taskIdentifier == taskIdentifier)
        
        guard case .download(let url) = result.transfer, url == nil else {
            XCTFail()
            return
        }
    }
    
    func testCacheResultWithURL() throws {
        let file = FilenamingWithAppMetaDataVersion(fileUUID: UUID().uuidString, fileVersion: 1, appMetaDataVersion: nil)
        try backgroundCache.initializeDownloadCache(file: file, taskIdentifer: taskIdentifier)
        
        let url = URL(fileURLWithPath: "foobly")
        let response = HTTPURLResponse(url: URL(fileURLWithPath: ""), mimeType: "text/plain", expectedContentLength: 0, textEncodingName: nil)
        try backgroundCache.cacheDownloadResult(taskIdentifer: taskIdentifier, response: response, localURL: url)
        
        guard let result = try NetworkCache.fetchSingleRow(db: database, where:
            taskIdentifier == NetworkCache.taskIdentifierField.description) else {
            XCTFail()
            return
        }
        
        guard let transfer = result.transfer else {
            XCTFail()
            return
        }
        switch transfer {
        case .upload:
            XCTFail()
        case .download(let downloadUrl):
            XCTAssert(downloadUrl?.path == url.path)
        }
    }
    
    func testLookupAndRemoveCacheWithDownloadCachePresent() throws {
        let file = FilenamingWithAppMetaDataVersion(fileUUID: UUID().uuidString, fileVersion: 1, appMetaDataVersion: nil)
        try backgroundCache.initializeDownloadCache(file: file, taskIdentifer: taskIdentifier)
        
        let url = URL(fileURLWithPath: "foobly")
        let response = HTTPURLResponse(url: URL(fileURLWithPath: ""), mimeType: "text/plain", expectedContentLength: 0, textEncodingName: nil)
        try backgroundCache.cacheDownloadResult(taskIdentifer: taskIdentifier, response: response, localURL: url)
        
        guard let result = try backgroundCache.lookupAndRemoveCache(file: file, download: true) else {
            XCTFail()
            return
        }
                
        let present = try NetworkCache.isRow(db: database, where: NetworkCache.idField.description == result.id)
        XCTAssert(!present)
    }
    
    func testLookupAndRemoveCacheWithDownloadCacheAbsent() throws {
        let file = FileObject(fileUUID: UUID().uuidString, fileVersion: 1)
        try backgroundCache.initializeUploadCache(file: file, taskIdentifer: taskIdentifier)
                
        let result = try backgroundCache.lookupAndRemoveCache(file: file, download: true)
        XCTAssert(result == nil)
                
        let present = try NetworkCache.isRow(db: database, where: NetworkCache.fileUUIDField.description == file.fileUUID)
        XCTAssert(present)
    }
    
    func testLookupAndRemoveCacheWithUploadCachePresent() throws {
        let file = FileObject(fileUUID: UUID().uuidString, fileVersion: 1)
        try backgroundCache.initializeUploadCache(file: file, taskIdentifer: taskIdentifier)
                
        try backgroundCache.cacheUploadResult(taskIdentifer: taskIdentifier, uploadBody: ["Foo": "bar"])
        
        guard let _ = try backgroundCache.lookupAndRemoveCache(file: file, download: false) else {
            XCTFail()
            return
        }
                
        let present = try NetworkCache.isRow(db: database, where: NetworkCache.fileUUIDField.description == file.fileUUID)
        XCTAssert(!present)
    }
    
    func testLookupAndRemoveCacheWithUploadCacheAbsent() throws {
        let file = FilenamingWithAppMetaDataVersion(fileUUID: UUID().uuidString, fileVersion: 1, appMetaDataVersion: nil)
        try backgroundCache.initializeDownloadCache(file: file, taskIdentifer: taskIdentifier)
        
        let url = URL(fileURLWithPath: "foobly")
        let response = HTTPURLResponse(url: URL(fileURLWithPath: ""), mimeType: "text/plain", expectedContentLength: 0, textEncodingName: nil)
        try backgroundCache.cacheDownloadResult(taskIdentifer: taskIdentifier, response: response, localURL: url)
        
        let result = try backgroundCache.lookupAndRemoveCache(file: file, download: false)
        XCTAssert(result == nil)
        
        let present = try NetworkCache.isRow(db: database, where: NetworkCache.fileUUIDField.description == file.fileUUID)
        XCTAssert(present)
    }
    
    func testRemoveCache() throws {
        let file = FileObject(fileUUID: UUID().uuidString, fileVersion: 1)
        try backgroundCache.initializeUploadCache(file: file, taskIdentifer: taskIdentifier)
        
        try backgroundCache.removeCache(taskIdentifer: taskIdentifier)
    }
}
