import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
@testable import TestsCommon
import iOSShared

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
        let fileUUID = UUID().uuidString
        try backgroundCache.initializeUploadCache(fileUUID: fileUUID, uploadObjectTrackerId: -1, taskIdentifer: taskIdentifier)
        
        guard let result = try NetworkCache.fetchSingleRow(db: database, where:
            taskIdentifier == NetworkCache.taskIdentifierField.description) else {
            XCTFail()
            return
        }
        
        XCTAssert(result.uuid.uuidString == fileUUID)
        XCTAssert(result.taskIdentifier == taskIdentifier)
        
        guard case .upload(let body) = result.transfer, body == nil else {
            XCTFail()
            return
        }
    }
    
    func testInitializeDownloadCache() throws {
        let file = FileObject(fileUUID: UUID().uuidString, fileVersion: 1, trackerId: -1)
        try backgroundCache.initializeDownloadCache(file: file, taskIdentifer: taskIdentifier)
        
        guard let result = try NetworkCache.fetchSingleRow(db: database, where:
            taskIdentifier == NetworkCache.taskIdentifierField.description) else {
            XCTFail()
            return
        }
        
        XCTAssert(result.fileVersion == file.fileVersion)
        XCTAssert(result.uuid.uuidString == file.fileUUID)
        XCTAssert(result.taskIdentifier == taskIdentifier)
        
        guard case .download(let url) = result.transfer, url == nil else {
            XCTFail()
            return
        }
    }
    
    func testCacheResultWithURL() throws {
        let file = FileObject(fileUUID: UUID().uuidString, fileVersion: 1, trackerId: -1)
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
        case .request:
            XCTFail()
        }
    }
}
