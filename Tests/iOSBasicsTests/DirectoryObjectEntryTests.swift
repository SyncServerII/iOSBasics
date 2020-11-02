import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared

final class DirectoryObjectEntryTests: XCTestCase {
    var database: Connection!
    let fileGroupUUID = UUID()
    var entry:DirectoryObjectEntry!
    let objectType = "Foobar"
    
    override func setUp() {
        super.setUp()
        set(logLevel: .trace)
        do {
            database = try Connection(.inMemory)
            entry = try DirectoryObjectEntry(db: database, objectType: objectType, fileGroupUUID: fileGroupUUID, sharingGroupUUID: UUID(), cloudStorageType: .Dropbox)
        } catch {
            XCTFail()
            return
        }
    }
    
    func assertContentsCorrect(entry1: DirectoryObjectEntry, entry2: DirectoryObjectEntry) {
        XCTAssert(entry1.fileGroupUUID == entry2.fileGroupUUID)
        XCTAssert(entry1.sharingGroupUUID == entry2.sharingGroupUUID)
        XCTAssert(entry1.objectType == entry2.objectType)
    }
    
    func testCreateTable() throws {
        try DirectoryObjectEntry.createTable(db: database)
    }
    
    func testDoubleCreateTable() throws {
        try DirectoryObjectEntry.createTable(db: database)
        try DirectoryObjectEntry.createTable(db: database)
    }

    func testInsertIntoTable() throws {
        try DirectoryObjectEntry.createTable(db: database)
        try entry.insert()
    }
    
    func testFilterWhenRowNotFound() throws {
        try DirectoryObjectEntry.createTable(db: database)

        var count = 0
        try DirectoryObjectEntry.fetch(db: database,
            where: fileGroupUUID == DirectoryObjectEntry.fileGroupUUIDField.description) { row in
            count += 1
        }
        
        XCTAssert(count == 0)
    }
    
    func testFilterWhenRowFound() throws {
        try DirectoryObjectEntry.createTable(db: database)
        try entry.insert()
        
        var count = 0
        try DirectoryObjectEntry.fetch(db: database,
            where: fileGroupUUID == DirectoryObjectEntry.fileGroupUUIDField.description) { row in
            assertContentsCorrect(entry1: entry, entry2: row)
            count += 1
            XCTAssert(row.id != nil)
        }
        
        XCTAssert(count == 1)
    }
    
    func testFilterWhenTwoRowsFound() throws {
        try DirectoryObjectEntry.createTable(db: database)
        try entry.insert()
        
        // Second entry-- to have a different fileGroupUUID, the primary key.
        let entry2 = try DirectoryObjectEntry(db: database, objectType: "Foobar2", fileGroupUUID: UUID(), sharingGroupUUID: UUID(), cloudStorageType: .Dropbox)

        try entry2.insert()

        var count = 0
        try DirectoryObjectEntry.fetch(db: database) { row in
            count += 1
        }
        
        XCTAssert(count == 2)
    }
    
    func testUpdate() throws {
        try DirectoryObjectEntry.createTable(db: database)
        try entry.insert()
                
        let replacement = UUID()
        
        entry = try entry.update(setters:
            DirectoryObjectEntry.fileGroupUUIDField.description <- replacement
        )
                
        var count = 0
        try DirectoryObjectEntry.fetch(db: database,
            where: replacement == DirectoryObjectEntry.fileGroupUUIDField.description) { row in
            XCTAssert(row.fileGroupUUID == replacement, "\(row.fileGroupUUID)")
            count += 1
        }
        
        XCTAssert(entry.fileGroupUUID == replacement)
        
        XCTAssert(count == 1)
    }
    
    func testDelete() throws {
        try DirectoryObjectEntry.createTable(db: database)
        try entry.insert()
        
        try entry.delete()
    }
}

