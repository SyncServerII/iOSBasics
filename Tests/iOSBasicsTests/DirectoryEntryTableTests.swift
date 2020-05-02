import XCTest
@testable import iOSBasics
import SQLite

final class DirectoryEntryTableTests: XCTestCase {
    var database: Connection!
    let uuid = UUID().uuidString
    var entry:DirectoryEntry!
    
    override func setUp() {
        super.setUp()
        do {
            database = try Connection(.inMemory)
        } catch {
            XCTFail()
            return
        }
                
        entry = DirectoryEntry(db: database, fileUUID: uuid, mimeType: "text/plain", fileVersion: 1, sharingGroupUUID: UUID().uuidString, cloudStorageType: "Dropbox", appMetaData: "Stuff", appMetaDataVersion: 20, fileGroupUUID: UUID().uuidString)
    }
    
    func assertEntryContentsCorrect(row: DirectoryEntry) {
        XCTAssert(entry.fileUUID == row.fileUUID)
        XCTAssert(entry.mimeType == row.mimeType)
        XCTAssert(entry.fileVersion == row.fileVersion)
        XCTAssert(entry.sharingGroupUUID == row.sharingGroupUUID)
        XCTAssert(entry.cloudStorageType == row.cloudStorageType)
        XCTAssert(entry.appMetaData == row.appMetaData)
        XCTAssert(entry.appMetaDataVersion == row.appMetaDataVersion)
        XCTAssert(entry.fileGroupUUID == row.fileGroupUUID)
    }
    
    func testCreateTable() throws {
        try DirectoryEntry.createTable(db: database)
    }
    
    func testDoubleCreateTable() throws {
        try DirectoryEntry.createTable(db: database)
        try DirectoryEntry.createTable(db: database)
    }
    
    func testInsertIntoTable() throws {
        try DirectoryEntry.createTable(db: database)

        try entry.insert()
    }
    
    func testFilterWhenRowNotFound() throws {
        try DirectoryEntry.createTable(db: database)

        var count = 0
        try DirectoryEntry.fetch(db: database,
            where: uuid == DirectoryEntry.fileUUIDExpression) { row in
            count += 1
        }
        
        XCTAssert(count == 0)
    }
    
    func testFilterWhenRowFound() throws {
        try DirectoryEntry.createTable(db: database)
        try entry.insert()
        
        var count = 0
        try DirectoryEntry.fetch(db: database,
            where: uuid == DirectoryEntry.fileUUIDExpression) { row in
            assertEntryContentsCorrect(row: row)
            count += 1
        }
        
        XCTAssert(count == 1)
    }
    
    func testUpdate() throws {
        try DirectoryEntry.createTable(db: database)
        try entry.insert()
                
        let replacement = "foo"
        
        try entry.update(db: database, setters:
            DirectoryEntry.fileUUIDExpression <- replacement
        )
        
        var count = 0
        try DirectoryEntry.fetch(db: database,
            where: replacement == DirectoryEntry.fileUUIDExpression) { row in
            XCTAssert(row.fileUUID == replacement, row.fileUUID)
            count += 1
        }
        
        XCTAssert(entry.fileUUID == replacement)
        
        XCTAssert(count == 1)
    }
    
    func testDelete() throws {
        try DirectoryEntry.createTable(db: database)
        try entry.insert()
        
        try entry.delete()
    }

    static var allTests = [
        ("testCreateTable", testCreateTable),
    ]
}
