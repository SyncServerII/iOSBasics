import XCTest
@testable import iOSBasics
import SQLite
import ServerShared

final class DirectoryEntryTableTests: XCTestCase {
    var database: Connection!
    let uuid = UUID().uuidString
    var entry:DirectoryEntry!
    
    override func setUp() {
        super.setUp()
        do {
            database = try Connection(.inMemory)
            entry = try DirectoryEntry(db: database, fileUUID: uuid, mimeType: "text/plain", fileVersion: 1, sharingGroupUUID: UUID().uuidString, cloudStorageType: "Dropbox", deletedLocally: false, deletedOnServer: true, appMetaData: "Stuff", appMetaDataVersion: 20, fileGroupUUID: UUID().uuidString, goneReason: GoneReason.userRemoved.rawValue)
        } catch {
            XCTFail()
            return
        }
    }
    
    func assertEntryContentsCorrect(entry1: DirectoryEntry, entry2: DirectoryEntry) {
        XCTAssert(entry1.fileUUID == entry2.fileUUID)
        XCTAssert(entry1.mimeType == entry2.mimeType)
        XCTAssert(entry1.fileVersion == entry2.fileVersion)
        XCTAssert(entry1.sharingGroupUUID == entry2.sharingGroupUUID)
        XCTAssert(entry1.cloudStorageType == entry2.cloudStorageType)
        XCTAssert(entry1.deletedLocally == entry2.deletedLocally)
        XCTAssert(entry1.deletedOnServer == entry2.deletedOnServer)
        XCTAssert(entry1.appMetaData == entry2.appMetaData)
        XCTAssert(entry1.appMetaDataVersion == entry2.appMetaDataVersion)
        XCTAssert(entry1.fileGroupUUID == entry2.fileGroupUUID)
        XCTAssert(entry1.goneReason == entry2.goneReason)
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
            where: uuid == DirectoryEntry.fileUUIDField.description) { row in
            count += 1
        }
        
        XCTAssert(count == 0)
    }
    
    func testFilterWhenRowFound() throws {
        try DirectoryEntry.createTable(db: database)
        try entry.insert()
        
        var count = 0
        try DirectoryEntry.fetch(db: database,
            where: uuid == DirectoryEntry.fileUUIDField.description) { row in
            assertEntryContentsCorrect(entry1: entry, entry2: row)
            count += 1
        }
        
        XCTAssert(count == 1)
    }
    
    func testFilterWhenTwoRowsFound() throws {
        try DirectoryEntry.createTable(db: database)
        try entry.insert()
        
        // Second entry-- to have a different fileUUID, the primary key.
        let entry2 = try DirectoryEntry(db: database, fileUUID: UUID().uuidString, mimeType: "text/plain", fileVersion: 1, sharingGroupUUID: UUID().uuidString, cloudStorageType: "Dropbox", deletedLocally: false, deletedOnServer: true, appMetaData: "Stuff", appMetaDataVersion: 20, fileGroupUUID: UUID().uuidString, goneReason: GoneReason.userRemoved.rawValue)

        try entry2.insert()

        var count = 0
        try DirectoryEntry.fetch(db: database) { row in
            count += 1
        }
        
        XCTAssert(count == 2)
    }
    
    func testUpdate() throws {
        try DirectoryEntry.createTable(db: database)
        try entry.insert()
                
        let replacement = "foo"
        
        entry = try entry.update(setters:
            DirectoryEntry.fileUUIDField.description <- replacement
        )
                
        var count = 0
        try DirectoryEntry.fetch(db: database,
            where: replacement == DirectoryEntry.fileUUIDField.description) { row in
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
