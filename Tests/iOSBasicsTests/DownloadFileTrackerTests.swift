import XCTest
@testable import iOSBasics
import SQLite
import ServerShared

class DownloadFileTrackerTests: XCTestCase {
    var database: Connection!
    let fileUUID = UUID()
    var entry:DownloadFileTracker!
    
    override func setUpWithError() throws {
        database = try Connection(.inMemory)
        entry = try DownloadFileTracker(db: database, downloadObjectTrackerId: 0, status: .downloaded, fileUUID: fileUUID, fileVersion: 0, localURL: nil)
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func assertContentsCorrect(entry1: DownloadFileTracker, entry2: DownloadFileTracker) {
        XCTAssert(entry1.status == entry2.status)
        XCTAssert(entry1.fileUUID == entry2.fileUUID)
        XCTAssert(entry1.fileVersion == entry2.fileVersion)
        XCTAssert(entry1.localURL?.path == entry2.localURL?.path)
        XCTAssert(entry1.downloadObjectTrackerId == entry2.downloadObjectTrackerId)
    }

    func testCreateTable() throws {
        try DownloadFileTracker.createTable(db: database)
    }
    
    func testDoubleCreateTable() throws {
        try DownloadFileTracker.createTable(db: database)
        try DownloadFileTracker.createTable(db: database)
    }
    
    func testInsertIntoTable() throws {
        try DownloadFileTracker.createTable(db: database)
        try entry.insert()
    }
    
    func testFilterWhenRowNotFound() throws {
        try DownloadFileTracker.createTable(db: database)
        
        var count = 0
        try DownloadFileTracker.fetch(db: database,
            where: fileUUID == DownloadFileTracker.fileUUIDField.description) { row in
            count += 1
        }
        
        XCTAssert(count == 0)
    }
    
    func testFilterWhenRowFound() throws {
        try DownloadFileTracker.createTable(db: database)
        try entry.insert()
        
        var count = 0
        try DownloadFileTracker.fetch(db: database,
            where: fileUUID == DownloadFileTracker.fileUUIDField.description) { row in
            assertContentsCorrect(entry1: entry, entry2: row)
            count += 1
        }
        
        XCTAssert(count == 1)
    }
    
    func testFilterWhenTwoRowsFound() throws {
        try DownloadFileTracker.createTable(db: database)
        try entry.insert()
        
        // Second entry-- to have a different fileUUID, the primary key.
        let entry2 = try DownloadFileTracker(db: database, downloadObjectTrackerId: 0, status: .downloaded, fileUUID: UUID(), fileVersion: 0, localURL: nil)

        try entry2.insert()

        var count = 0
        try DownloadFileTracker.fetch(db: database) { row in
            count += 1
        }
        
        XCTAssert(count == 2)
    }
    
    func testUpdate() throws {
        try DownloadFileTracker.createTable(db: database)
        try entry.insert()
                
        let replacement = UUID()
        
        entry = try entry.update(setters:
            DownloadFileTracker.fileUUIDField.description <- replacement
        )
                
        var count = 0
        try DownloadFileTracker.fetch(db: database,
            where: replacement == DownloadFileTracker.fileUUIDField.description) { row in
            XCTAssert(row.fileUUID == replacement, "\(row.fileUUID)")
            count += 1
        }
        
        XCTAssert(entry.fileUUID == replacement)
        
        XCTAssert(count == 1)
    }
    
    func testDelete() throws {
        try DownloadFileTracker.createTable(db: database)
        try entry.insert()
        
        try entry.delete()
    }
    
    func testChangeStatusOfExactlyOneRecord() throws {
        try DownloadFileTracker.createTable(db: database)
        
        let originalStatus: DownloadFileTracker.Status = .notStarted
        
        let e1 = try DownloadFileTracker(db: database, downloadObjectTrackerId: 0, status: originalStatus, fileUUID: UUID(), fileVersion: 0, localURL: nil)
        try e1.insert()
        
        let e2 = try DownloadFileTracker(db: database, downloadObjectTrackerId: 0, status: originalStatus, fileUUID: fileUUID, fileVersion: 0, localURL: nil)
        try e2.insert()
        
        try e1.update(setters:
            DownloadFileTracker.statusField.description <- .downloaded)
            
        guard let e2Copy = try DownloadFileTracker.fetchSingleRow(db: database, where: e2.id == DownloadFileTracker.idField.description) else {
            XCTFail()
            return
        }
        
        XCTAssert(e2Copy.status == originalStatus, "\(e2Copy.status)")
    }
}
