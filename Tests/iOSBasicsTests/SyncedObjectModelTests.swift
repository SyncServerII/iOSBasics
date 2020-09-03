import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
// @testable import TestsCommon

class SyncedObjectModelTests: XCTestCase {
    var database: Connection!
    let fileGroupUUID = UUID()
    var entry:SyncedObjectModel!
    
    override func setUpWithError() throws {
        database = try Connection(.inMemory)
        entry = try SyncedObjectModel(db: database, fileGroupUUID: fileGroupUUID, objectType: "someObjectType", sharingGroupUUID: UUID())
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testCreateTable() throws {
        try SyncedObjectModel.createTable(db: database)
    }
    
    func testDoubleCreateTable() throws {
        try SyncedObjectModel.createTable(db: database)
        try SyncedObjectModel.createTable(db: database)
    }
    
    func testInsertIntoTable() throws {
        try SyncedObjectModel.createTable(db: database)
        try entry.insert()
    }
    
    func testFilterWhenRowNotFound() throws {
        try SyncedObjectModel.createTable(db: database)
        
        var count = 0
        try SyncedObjectModel.fetch(db: database,
            where: fileGroupUUID == SyncedObjectModel.fileGroupUUIDField.description) { row in
            count += 1
        }
        
        XCTAssert(count == 0)
    }

    func testFilterWhenRowFound() throws {
        try SyncedObjectModel.createTable(db: database)
        try entry.insert()
        
        var count = 0
        try SyncedObjectModel.fetch(db: database,
            where: fileGroupUUID == SyncedObjectModel.fileGroupUUIDField.description) { row in
            XCTAssertEqual(entry, row)
            count += 1
        }
        
        XCTAssert(count == 1)
    }
    
    func testFilterWhenTwoRowsFound() throws {
        try SyncedObjectModel.createTable(db: database)
        try entry.insert()
        
        // Second entry-- to have a different fileGroupUUID, the primary key.
        let entry2 = try SyncedObjectModel(db: database, fileGroupUUID: UUID(), objectType: "someObjectType", sharingGroupUUID: UUID())

        try entry2.insert()

        var count = 0
        try SyncedObjectModel.fetch(db: database) { row in
            count += 1
        }
        
        XCTAssert(count == 2)
    }

    func testUpdate() throws {
        try SyncedObjectModel.createTable(db: database)
        try entry.insert()
                
        let replacement = UUID()
        
        entry = try entry.update(setters:
            SyncedObjectModel.fileGroupUUIDField.description <- replacement
        )
                
        var count = 0
        try SyncedObjectModel.fetch(db: database,
            where: replacement == SyncedObjectModel.fileGroupUUIDField.description) { row in
            XCTAssert(row.fileGroupUUID == replacement, "\(row.fileGroupUUID)")
            count += 1
        }
        
        XCTAssert(entry.fileGroupUUID == replacement)
        
        XCTAssert(count == 1)
    }

    func testDelete() throws {
        try SyncedObjectModel.createTable(db: database)
        try entry.insert()
        
        try entry.delete()
        
        var count = 0
        try SyncedObjectModel.fetch(db: database) { row in
            count += 1
        }
        
        XCTAssert(count == 0)
    }
}
