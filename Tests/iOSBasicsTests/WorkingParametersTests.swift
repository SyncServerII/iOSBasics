import XCTest
@testable import iOSBasics
import SQLite
import ServerShared

class WorkingParametersTests: XCTestCase {
    var database: Connection!
    let fetchingSharingGroup = UUID()
    var entry:WorkingParameters!
    
    override func setUpWithError() throws {
        database = try Connection(.inMemory)
        entry = try WorkingParameters(db: database, currentSharingGroup: UUID())
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func assertContentsCorrect(entry1: WorkingParameters, entry2: WorkingParameters) {
        XCTAssert(entry1.currentSharingGroup == entry2.currentSharingGroup)
    }

    func testCreateTable() throws {
        try WorkingParameters.createTable(db: database)
    }
    
    func testDoubleCreateTable() throws {
        try WorkingParameters.createTable(db: database)
        try WorkingParameters.createTable(db: database)
    }
    
    func testInsertIntoTable() throws {
        try WorkingParameters.createTable(db: database)
        try entry.insert()
    }
    
    func testUpdate() throws {
        try WorkingParameters.createTable(db: database)
        try entry.insert()
                
        let replacement = UUID()
        
        entry = try entry.update(setters:
            WorkingParameters.currentSharingGroupField.description <- replacement
        )
                
        var count = 0
        try WorkingParameters.fetch(db: database) { row in
            XCTAssert(row.currentSharingGroup == replacement, "\(String(describing: row.currentSharingGroup))")
            count += 1
        }
        
        XCTAssert(entry.currentSharingGroup == replacement)
        
        XCTAssert(count == 1)
    }
    
    func testDelete() throws {
        try WorkingParameters.createTable(db: database)
        try entry.insert()
        
        try entry.delete()
    }
    
    func testSetup() throws {
        try WorkingParameters.createTable(db: database)
        try WorkingParameters.setup(db: database)
        let _ = try WorkingParameters.singleton(db: database)
        try WorkingParameters.setup(db: database)
        let _ = try WorkingParameters.singleton(db: database)
    }
}
