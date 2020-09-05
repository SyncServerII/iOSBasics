import XCTest
@testable import iOSBasics
import SQLite
import ServerShared

class DeclaredFileModelTests: XCTestCase {
    var database: Connection!
    let fileGroupUUID = UUID()
    var entry:DeclaredFileModel!
    
    override func setUpWithError() throws {
        database = try Connection(.inMemory)
        entry = try DeclaredFileModel(db: database, fileGroupUUID: fileGroupUUID, uuid: UUID(), mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: "Foo", changeResolverName: "Bar")
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testCreateTable() throws {
        try DeclaredFileModel.createTable(db: database)
    }
    
    func testDoubleCreateTable() throws {
        try DeclaredFileModel.createTable(db: database)
        try DeclaredFileModel.createTable(db: database)
    }
    
    func testInsertIntoTable() throws {
        try DeclaredFileModel.createTable(db: database)
        try entry.insert()
    }

    func testFilterWhenRowNotFound() throws {
        try DeclaredFileModel.createTable(db: database)
        
        var count = 0
        try DeclaredFileModel.fetch(db: database,
            where: fileGroupUUID == DeclaredFileModel.fileGroupUUIDField.description) { row in
            count += 1
        }
        
        XCTAssert(count == 0)
    }
    
    func testFilterWhenRowFound() throws {
        try DeclaredFileModel.createTable(db: database)
        try entry.insert()
        
        var count = 0
        try DeclaredFileModel.fetch(db: database,
            where: fileGroupUUID == DeclaredFileModel.fileGroupUUIDField.description) { row in
            XCTAssertEqual(entry, row)
            count += 1
        }
        
        XCTAssert(count == 1)
    }
    
    func testFilterWhenTwoRowsFound() throws {
        try DeclaredFileModel.createTable(db: database)
        try entry.insert()
        
        // Second entry-- to have a different fileGroupUUID, the primary key.
        let entry2 = try DeclaredFileModel(db: database, fileGroupUUID: UUID(), uuid: UUID(), mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: "Foo2", changeResolverName: "Bar2")

        try entry2.insert()

        var count = 0
        try DeclaredFileModel.fetch(db: database) { row in
            count += 1
        }
        
        XCTAssert(count == 2)
    }
    
    func testUpdate() throws {
        try DeclaredFileModel.createTable(db: database)
        try entry.insert()
                
        let replacement = UUID()
        
        entry = try entry.update(setters:
            DeclaredFileModel.fileGroupUUIDField.description <- replacement
        )
                
        var count = 0
        try DeclaredFileModel.fetch(db: database,
            where: replacement == DeclaredFileModel.fileGroupUUIDField.description) { row in
            XCTAssert(row.fileGroupUUID == replacement, "\(row.fileGroupUUID)")
            count += 1
        }
        
        XCTAssert(entry.fileGroupUUID == replacement)
        
        XCTAssert(count == 1)
    }
    
    func testDelete() throws {
        try DeclaredFileModel.createTable(db: database)
        try entry.insert()
        
        try entry.delete()
        
        var count = 0
        try DeclaredFileModel.fetch(db: database) { row in
            count += 1
        }
        
        XCTAssert(count == 0)
    }
}
