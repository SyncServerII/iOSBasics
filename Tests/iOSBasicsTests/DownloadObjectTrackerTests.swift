import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared

class DownloadObjectTrackerTests: XCTestCase {
    var database: Connection!
    let fileGroupUUID = UUID()
    var entry:DownloadObjectTracker!
    
    override func setUpWithError() throws {
        set(logLevel: .trace)
        database = try Connection(.inMemory)
        entry = try DownloadObjectTracker(db: database, fileGroupUUID: fileGroupUUID)
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func assertContentsCorrect(entry1: DownloadObjectTracker, entry2: DownloadObjectTracker) {
        XCTAssert(entry1.fileGroupUUID == entry2.fileGroupUUID)
    }

    func testCreateTable() throws {
        try DownloadObjectTracker.createTable(db: database)
    }
    
    func testDoubleCreateTable() throws {
        try DownloadObjectTracker.createTable(db: database)
        try DownloadObjectTracker.createTable(db: database)
    }
    
    func testInsertIntoTable() throws {
        try DownloadObjectTracker.createTable(db: database)
        try entry.insert()
    }
    
    func testFilterWhenRowNotFound() throws {
        try DownloadObjectTracker.createTable(db: database)
        
        var count = 0
        try DownloadObjectTracker.fetch(db: database,
            where: fileGroupUUID == DownloadObjectTracker.fileGroupUUIDField.description) { row in
            count += 1
        }
        
        XCTAssert(count == 0)
    }
    
    func testFilterWhenRowFound() throws {
        try DownloadObjectTracker.createTable(db: database)
        try entry.insert()
        
        var count = 0
        try DownloadObjectTracker.fetch(db: database,
            where: fileGroupUUID == DownloadObjectTracker.fileGroupUUIDField.description) { row in
            assertContentsCorrect(entry1: entry, entry2: row)
            count += 1
        }
        
        XCTAssert(count == 1)
    }
    
    func testFilterWhenTwoRowsFound() throws {
        try DownloadObjectTracker.createTable(db: database)
        try entry.insert()
        
        // Second entry-- to have a different fileUUID, the primary key.
        let entry2 = try DownloadObjectTracker(db: database,fileGroupUUID: UUID())

        try entry2.insert()

        var count = 0
        try DownloadObjectTracker.fetch(db: database) { row in
            count += 1
        }
        
        XCTAssert(count == 2)
    }
    
    func testUpdate() throws {
        try DownloadObjectTracker.createTable(db: database)
        try entry.insert()
                
        let replacement = UUID()
        
        entry = try entry.update(setters:
            DownloadObjectTracker.fileGroupUUIDField.description <- replacement
        )
                
        var count = 0
        try DownloadObjectTracker.fetch(db: database,
            where: replacement == DownloadObjectTracker.fileGroupUUIDField.description) { row in
            XCTAssert(row.fileGroupUUID == replacement, "\(row.fileGroupUUID)")
            count += 1
        }
        
        XCTAssert(entry.fileGroupUUID == replacement)
        
        XCTAssert(count == 1)
    }
    
    func testDelete() throws {
        try DownloadObjectTracker.createTable(db: database)
        try entry.insert()
        
        try entry.delete()
    }
    
    func testDownloadsWithAllScope() throws {
        try DownloadObjectTracker.createTable(db: database)
        try entry.insert()
        try DownloadFileTracker.createTable(db: database)

        // 1) No downloads-- because db is empty
        let downloads1 = try DownloadObjectTracker.downloadsWith(status: .downloaded, scope: .all, db: database)
        XCTAssert(downloads1.count == 0)
        
        // 2) No downloads because of no match
        let fileTracker1 = try DownloadFileTracker(db: database, downloadObjectTrackerId: entry.id, status: .downloaded, fileUUID: UUID(), fileVersion: 0, localURL: nil)
        try fileTracker1.insert()
        
        let fileTracker2 = try DownloadFileTracker(db: database, downloadObjectTrackerId: entry.id, status: .downloading, fileUUID: UUID(), fileVersion: 0, localURL: nil)
        try fileTracker2.insert()

        let downloads2 = try DownloadObjectTracker.downloadsWith(status: .downloaded, scope: .all, db: database)
        XCTAssert(downloads2.count == 0)

        // 3) A match
        try fileTracker2.update(setters: DownloadFileTracker.statusField.description <- .downloaded)
        let downloads3 = try DownloadObjectTracker.downloadsWith(status: .downloaded, scope: .all, db: database)
        XCTAssert(downloads3.count == 1)
    }
    
    func testDownloadsWithSomeScope() throws {
        try DownloadObjectTracker.createTable(db: database)
        try entry.insert()
        try DownloadFileTracker.createTable(db: database)

        // 1) No downloads-- because db is empty
        let downloads1 = try DownloadObjectTracker.downloadsWith(status: .downloaded, scope: .some, db: database)
        XCTAssert(downloads1.count == 0)
        
        // 2) Downloads
        let fileTracker1 = try DownloadFileTracker(db: database, downloadObjectTrackerId: entry.id, status: .downloaded, fileUUID: UUID(), fileVersion: 0, localURL: nil)
        try fileTracker1.insert()
        
        let fileTracker2 = try DownloadFileTracker(db: database, downloadObjectTrackerId: entry.id, status: .downloading, fileUUID: UUID(), fileVersion: 0, localURL: nil)
        try fileTracker2.insert()

        let downloads2 = try DownloadObjectTracker.downloadsWith(status: .downloaded, scope: .some, db: database)
        guard downloads2.count == 1 else {
            XCTFail()
            return
        }
        
        guard downloads2[0].files.count == 1 else {
            XCTFail()
            return
        }
        
        let file = downloads2[0].files[0]
        XCTAssert(file.fileUUID == fileTracker1.fileUUID)
    }
}
