import XCTest
@testable import iOSBasics
import SQLite
import ServerShared

class UploadObjectTrackerTests: XCTestCase {
    var database: Connection!
    let fileGroupUUID = UUID()
    var entry:UploadObjectTracker!
    
    override func setUpWithError() throws {
        database = try Connection(.inMemory)
        entry = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID, v0Upload: true)
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func assertContentsCorrect(entry1: UploadObjectTracker, entry2: UploadObjectTracker) {
        XCTAssert(entry1.fileGroupUUID == entry2.fileGroupUUID)
    }

    func testCreateTable() throws {
        try UploadObjectTracker.createTable(db: database)
    }
    
    func testDoubleCreateTable() throws {
        try UploadObjectTracker.createTable(db: database)
        try UploadObjectTracker.createTable(db: database)
    }
    
    func testInsertIntoTable() throws {
        try UploadObjectTracker.createTable(db: database)
        try entry.insert()
    }
    
    func testFilterWhenRowNotFound() throws {
        try UploadObjectTracker.createTable(db: database)
        
        var count = 0
        try UploadObjectTracker.fetch(db: database,
            where: fileGroupUUID == UploadObjectTracker.fileGroupUUIDField.description) { row in
            count += 1
        }
        
        XCTAssert(count == 0)
    }
    
    func testFilterWhenRowFound() throws {
        try UploadObjectTracker.createTable(db: database)
        try entry.insert()
        
        var count = 0
        try UploadObjectTracker.fetch(db: database,
            where: fileGroupUUID == UploadObjectTracker.fileGroupUUIDField.description) { row in
            assertContentsCorrect(entry1: entry, entry2: row)
            count += 1
        }
        
        XCTAssert(count == 1)
    }
    
    func testFilterWhenTwoRowsFound() throws {
        try UploadObjectTracker.createTable(db: database)
        try entry.insert()
        
        // Second entry-- to have a different fileGroupUUID, the primary key.
        let entry2 = try UploadObjectTracker(db: database, fileGroupUUID: UUID(), v0Upload: false)

        try entry2.insert()

        var count = 0
        try UploadObjectTracker.fetch(db: database) { row in
            count += 1
        }
        
        XCTAssert(count == 2)
    }
    
    func testUpdate() throws {
        try UploadObjectTracker.createTable(db: database)
        try entry.insert()
                
        let replacement = UUID()
        
        entry = try entry.update(setters:
            UploadObjectTracker.fileGroupUUIDField.description <- replacement
        )
                
        var count = 0
        try UploadObjectTracker.fetch(db: database,
            where: replacement == UploadObjectTracker.fileGroupUUIDField.description) { row in
            XCTAssert(row.fileGroupUUID == replacement, "\(row.fileGroupUUID)")
            count += 1
        }
        
        XCTAssert(entry.fileGroupUUID == replacement)
        
        XCTAssert(count == 1)
    }
    
    func testDelete() throws {
        try UploadObjectTracker.createTable(db: database)
        try entry.insert()
        
        try entry.delete()
    }
}
