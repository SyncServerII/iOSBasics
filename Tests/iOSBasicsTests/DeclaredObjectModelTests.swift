import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared

class DeclaredObjectModelTests: XCTestCase {
    var database: Connection!
    let fileGroupUUID = UUID()
    var entry:DeclaredObjectModel!
    let fileDeclaration = FileDeclaration(fileLabel: "file1", mimeTypes: [.jpeg], changeResolverName: nil)
    let objectType = "Foo"
    
    override func setUpWithError() throws {
        database = try Connection(.inMemory)
        entry = try DeclaredObjectModel(db: database, objectType: objectType, files: [fileDeclaration])
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
            where: objectType == DeclaredObjectModel.objectTypeField.description) { row in
            count += 1
        }
        
        XCTAssert(count == 0)
    }
    
    func testFilterWhenRowFound() throws {
        try DeclaredObjectModel.createTable(db: database)
        try entry.insert()
        
        var count = 0
        try DeclaredObjectModel.fetch(db: database,
            where: objectType == DeclaredObjectModel.objectTypeField.description) { row in
            XCTAssertEqual(entry, row)
            count += 1
        }
        
        XCTAssert(count == 1)
    }
    
    func testFilterWhenTwoRowsFound() throws {
        try DeclaredObjectModel.createTable(db: database)
        try entry.insert()
        
        // Second entry-- to have a different primary key.
        let entry2 = try DeclaredObjectModel(db: database, objectType: "OtherFoo", files: [fileDeclaration])
        
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
                
        let replacement = "OtherType"
        
        entry = try entry.update(setters:
            DeclaredObjectModel.objectTypeField.description <- replacement
        )
                
        var count = 0
        try DeclaredObjectModel.fetch(db: database,
            where: replacement == DeclaredObjectModel.objectTypeField.description) { row in
            XCTAssert(row.objectType == replacement, "\(row.objectType)")
            count += 1
        }
        
        XCTAssert(entry.objectType == replacement)
        
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
    
    func testProtocolConstructor() throws {
        try DeclaredObjectModel.createTable(db: database)

        let object = ObjectDeclaration(objectType: "Foobly", declaredFiles: [fileDeclaration])
        let entry = try DeclaredObjectModel(db: database, object: object)
        try entry.insert()
        
        var count = 0
        try DeclaredObjectModel.fetch(db: database,
            where: object.objectType == DeclaredObjectModel.objectTypeField.description) { row in
            XCTAssert(row.objectType ==  object.objectType, "\(row.objectType)")
            count += 1
        }
        
        XCTAssert(count == 1)
    }
    
    func testNoFilesInRegularConstructorFails() throws {
        try DeclaredObjectModel.createTable(db: database)

        do {
            let _ = try DeclaredObjectModel(db: database, objectType: "OtherFoo", files: [])
            XCTFail()
        } catch {
        }
    }
    
    func testNoFilesInProtocolConstructorFails() throws {
        try DeclaredObjectModel.createTable(db: database)
        let object = ObjectDeclaration(objectType: "Foobly", declaredFiles: [])

        do {
            let _ = try DeclaredObjectModel(db: database, object: object)
            XCTFail()
        } catch {
        }
    }
    
    // No declared objects present
    func testLookupWithNoObject() throws {
        try DeclaredObjectModel.createTable(db: database)
        
        do {
            let _ = try DeclaredObjectModel.lookup(objectType: "foo", db: database)
        } catch let error {
            guard let error = error as? DatabaseError else {
                XCTFail()
                return
            }
            XCTAssert(error == DatabaseError.noObject)
            return
        }

        XCTFail()
    }
    
    func testLookupWithObject() throws {
        try DeclaredObjectModel.createTable(db: database)
        try entry.insert()

        let result = try DeclaredObjectModel.lookup(objectType: objectType, db: database)
        
        XCTAssert(result.objectType == entry.objectType)
        XCTAssert(iOSBasics.equal(result.declaredFiles, try entry.getFiles()))
    }
    
    func testInsertDeclarationWithMultipleMimeTypes() throws {
        try DeclaredObjectModel.createTable(db: database)
        
        let mimeTypes:Set<MimeType> = [.jpeg, .png]
        let fileDeclaration = FileDeclaration(fileLabel: "file1", mimeTypes: mimeTypes, changeResolverName: nil)
        let objectType = "OtherFoo"
        let entry = try DeclaredObjectModel(db: database, objectType: objectType, files: [fileDeclaration])
        try entry.insert()
        
        let result = try DeclaredObjectModel.lookup(objectType: objectType, db: database)
        guard result.declaredFiles.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(result.declaredFiles[0].mimeTypes == mimeTypes)
        XCTAssert(result.objectType == entry.objectType)
        XCTAssert(iOSBasics.equal(result.declaredFiles, try entry.getFiles()))
    }
}

