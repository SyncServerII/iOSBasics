import XCTest
@testable import iOSBasics
import SQLite
import ServerShared

class DeclaredObjectModelTests: XCTestCase {
    var database: Connection!
    let fileGroupUUID = UUID()
    var entry:DeclaredObjectModel!
    
    override func setUpWithError() throws {
        database = try Connection(.inMemory)
        entry = try DeclaredObjectModel(db: database, fileGroupUUID: fileGroupUUID, objectType: "someObjectType", sharingGroupUUID: UUID())
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testCreateTable() throws {
        try DeclaredObjectModel.createTable(db: database)
    }
    
    func testDoubleCreateTable() throws {
        try DeclaredObjectModel.createTable(db: database)
        try DeclaredObjectModel.createTable(db: database)
    }
    
    func testInsertIntoTable() throws {
        try DeclaredObjectModel.createTable(db: database)
        try entry.insert()
    }
    
    func testFilterWhenRowNotFound() throws {
        try DeclaredObjectModel.createTable(db: database)
        
        var count = 0
        try DeclaredObjectModel.fetch(db: database,
            where: fileGroupUUID == DeclaredObjectModel.fileGroupUUIDField.description) { row in
            count += 1
        }
        
        XCTAssert(count == 0)
    }

    func testFilterWhenRowFound() throws {
        try DeclaredObjectModel.createTable(db: database)
        try entry.insert()
        
        var count = 0
        try DeclaredObjectModel.fetch(db: database,
            where: fileGroupUUID == DeclaredObjectModel.fileGroupUUIDField.description) { row in
            XCTAssertEqual(entry, row)
            count += 1
        }
        
        XCTAssert(count == 1)
    }
    
    func testFilterWhenTwoRowsFound() throws {
        try DeclaredObjectModel.createTable(db: database)
        try entry.insert()
        
        // Second entry-- to have a different fileGroupUUID, the primary key.
        let entry2 = try DeclaredObjectModel(db: database, fileGroupUUID: UUID(), objectType: "someObjectType", sharingGroupUUID: UUID())

        try entry2.insert()

        var count = 0
        try DeclaredObjectModel.fetch(db: database) { row in
            count += 1
        }
        
        XCTAssert(count == 2)
    }

    func testUpdate() throws {
        try DeclaredObjectModel.createTable(db: database)
        try entry.insert()
                
        let replacement = UUID()
        
        entry = try entry.update(setters:
            DeclaredObjectModel.fileGroupUUIDField.description <- replacement
        )
                
        var count = 0
        try DeclaredObjectModel.fetch(db: database,
            where: replacement == DeclaredObjectModel.fileGroupUUIDField.description) { row in
            XCTAssert(row.fileGroupUUID == replacement, "\(row.fileGroupUUID)")
            count += 1
        }
        
        XCTAssert(entry.fileGroupUUID == replacement)
        
        XCTAssert(count == 1)
    }

    func testDelete() throws {
        try DeclaredObjectModel.createTable(db: database)
        try entry.insert()
        
        try entry.delete()
        
        var count = 0
        try DeclaredObjectModel.fetch(db: database) { row in
            count += 1
        }
        
        XCTAssert(count == 0)
    }
    
    func testUpsert() throws {
        try DeclaredObjectModel.createTable(db: database)
        try entry.insert()
        
        let obj = ObjectBasics(fileGroupUUID: entry.fileGroupUUID, objectType: entry.objectType, sharingGroupUUID: entry.sharingGroupUUID)
        let declaredObject = try DeclaredObjectModel.upsert(object: obj, db: database)
                
        XCTAssert(entry == declaredObject)
        
        let obj2 = ObjectBasics(fileGroupUUID: UUID(), objectType: entry.objectType, sharingGroupUUID: entry.sharingGroupUUID)
        let declaredObject2 = try DeclaredObjectModel.upsert(object: obj2, db: database)
        
        XCTAssert(entry != declaredObject2)
    }
}
