import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
// @testable import TestsCommon

class NetworkCacheTests: XCTestCase {
    var database: Connection!
    let taskIdentifier = 100
    var entry:NetworkCache!
    
    override func setUpWithError() throws {
        database = try Connection(.inMemory)
        entry = try NetworkCache(db: database, taskIdentifier: taskIdentifier, fileUUID: UUID(), fileVersion: 1, transfer: nil)
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func assertContentsCorrect(entry1: NetworkCache, entry2: NetworkCache) {
        XCTAssert(entry1.taskIdentifier == entry2.taskIdentifier)
        XCTAssert(entry1.fileUUID == entry2.fileUUID)
        XCTAssert(entry1.fileVersion == entry2.fileVersion)
        XCTAssert(entry1.transfer == entry2.transfer)
    }
    
    func testUploadBody() throws {
        let uploadBody = UploadBody(dictionary: [
            "Foo": "Bar"
        ])
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(uploadBody)
        
        let decoder = JSONDecoder()
        let result = try decoder.decode(UploadBody.self, from: data)
        
        guard let str = result.dictionary["Foo"] as? String else {
            XCTFail()
            return
        }
        
        XCTAssert(str == "Bar")
    }
    
    func testNetworkTransferUploads() throws {
        let uploadBody = UploadBody(dictionary: [
            "Foo": "Bar"
        ])
        
        let transfer = NetworkTransfer.upload(uploadBody)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(transfer)
        
        let decoder = JSONDecoder()
        let result = try decoder.decode(NetworkTransfer.self, from: data)
        
        switch result {
        case .upload(let uploadBodyResult):
            XCTAssert(uploadBody == uploadBodyResult)
        default:
            XCTFail()
        }
    }
    
    func testNetworkTransferUploadsNilDictionary() throws {
        let transfer = NetworkTransfer.upload(nil)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(transfer)
        
        let decoder = JSONDecoder()
        let result = try decoder.decode(NetworkTransfer.self, from: data)
        
        switch result {
        case .upload(let uploadBodyResult):
            XCTAssert(uploadBodyResult == nil)
        default:
            XCTFail()
        }
    }
    
    func testNetworkTransferDownloads() throws {        
        let url = URL(fileURLWithPath: "Foobly")
        
        let transfer = NetworkTransfer.download(url)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(transfer)
        
        let decoder = JSONDecoder()
        let result = try decoder.decode(NetworkTransfer.self, from: data)
        
        switch result {
        case .download(let urlResult):
            XCTAssert(urlResult?.path == url.path)
        default:
            XCTFail()
        }
    }
    
    func testNetworkTransferDownloadsNilURL() throws {
        let transfer = NetworkTransfer.download(nil)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(transfer)
        
        let decoder = JSONDecoder()
        let result = try decoder.decode(NetworkTransfer.self, from: data)
        
        switch result {
        case .download(let urlResult):
            XCTAssert(urlResult == nil)
        default:
            XCTFail()
        }
    }

    func testCreateTable() throws {
        try NetworkCache.createTable(db: database)
    }
    
    func testDoubleCreateTable() throws {
        try NetworkCache.createTable(db: database)
        try NetworkCache.createTable(db: database)
    }
    
    func testInsertIntoTable() throws {
        try NetworkCache.createTable(db: database)
        try entry.insert()
    }
    
    func testFilterWhenRowNotFound() throws {
        try NetworkCache.createTable(db: database)

        var count = 0
        try NetworkCache.fetch(db: database,
            where: taskIdentifier == NetworkCache.taskIdentifierField.description) { row in
            count += 1
        }
        
        XCTAssert(count == 0)
    }
    
    func testFilterWhenRowFound() throws {
        try NetworkCache.createTable(db: database)
        try entry.insert()
        
        var count = 0
        try NetworkCache.fetch(db: database,
            where: taskIdentifier == NetworkCache.taskIdentifierField.description) { row in
            assertContentsCorrect(entry1: entry, entry2: row)
            count += 1
        }
        
        XCTAssert(count == 1)
    }
    
    func testFilterWhenTwoRowsFound() throws {
        try NetworkCache.createTable(db: database)
        try entry.insert()
        
        // Second entry-- to have a different primary key.
        let entry2 = try NetworkCache(db: database, taskIdentifier: taskIdentifier + 1, fileUUID: UUID(), fileVersion: 1, transfer: nil)

        try entry2.insert()

        var count = 0
        try NetworkCache.fetch(db: database) { row in
            count += 1
        }
        
        XCTAssert(count == 2)
    }
    
    func testUpdate() throws {
        try NetworkCache.createTable(db: database)
        try entry.insert()
                
        let replacement = UUID()
        
        entry = try entry.update(setters:
            NetworkCache.fileUUIDField.description <- replacement
        )
                
        var count = 0
        try NetworkCache.fetch(db: database,
            where: replacement == NetworkCache.fileUUIDField.description) { row in
            XCTAssert(row.fileUUID == replacement, "\(row.fileUUID)")
            count += 1
        }
        
        XCTAssert(entry.fileUUID == replacement)
        
        XCTAssert(count == 1)
    }
    
    func testDelete() throws {
        try NetworkCache.createTable(db: database)
        try entry.insert()
        
        try entry.delete()
    }
    
    // To test the URL Value extension
    func testSavingNilURL() throws {
        try NetworkCache.createTable(db: database)

        let entry = try NetworkCache(db: database, taskIdentifier: taskIdentifier, fileUUID: UUID(), fileVersion: 1,transfer: nil)
        try entry.insert()

        var count = 0
        try NetworkCache.fetch(db: database,
            where: taskIdentifier == NetworkCache.taskIdentifierField.description) { row in
            XCTAssert(row.transfer == nil)
            count += 1
        }
                
        XCTAssert(count == 1)
    }
    
    func testSingleRowFetch() throws {
        try NetworkCache.createTable(db: database)
        try entry.insert()
        
        let result = try NetworkCache.fetchSingleRow(db: database, where:
            taskIdentifier == NetworkCache.taskIdentifierField.description
        )
        
        guard result != nil else {
            XCTFail()
            return
        }
        
        XCTAssert(result?.id != nil)
        
        assertContentsCorrect(entry1: entry, entry2: result!)
    }
}
