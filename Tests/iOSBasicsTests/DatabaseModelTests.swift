import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared

class DatabaseModelTests: XCTestCase, ExpiryConfigurable {
    // MARK: ExpiryConfigurable
    let expiryDuration: TimeInterval = 100
    
    var database: Connection!
    let sharingGroupUUID = UUID()
    var entry:UploadFileTracker!
    override func setUpWithError() throws {
        database = try Connection(.inMemory)
        try UploadFileTracker.createTable(db: database)
        
        try UploadFileTracker.allMigrations(configuration: self, db: database)
        entry = try UploadFileTracker(db: database, uploadObjectTrackerId: 2, status: .notStarted, fileUUID: UUID(), mimeType: .text, fileVersion: 11, localURL: URL(fileURLWithPath: "Foobly"),  goneReason: .userRemoved, uploadCopy: false, checkSum: "Meebly", appMetaData: "Foo", uploadIndex: 0, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testNumberRowsWithNoRows() throws {
        XCTAssert(try UploadFileTracker.numberRows(db: database) == 0)
    }
    
    func testNumberRowsWithOneRow() throws {
        try entry.insert()
        XCTAssert(try UploadFileTracker.numberRows(db: database) == 1)
    }

    func testNumberRowsWithTwoRows() throws {
        try entry.insert()
        let entry2 = try UploadFileTracker(db: database, uploadObjectTrackerId: 2, status: .notStarted, fileUUID: UUID(), mimeType: .text, fileVersion: 11, localURL: URL(fileURLWithPath: "Foobly"), goneReason: .userRemoved, uploadCopy: false, checkSum: "Meebly", appMetaData: nil, uploadIndex: 1, uploadCount: 1, informAllButSelf: true, expiry: Date() + 100)
        try entry2.insert()
        XCTAssert(try UploadFileTracker.numberRows(db: database) == 2)
    }
    
    func testNumberRowsWithWhereClause() throws {
        try entry.insert()
        let entry2 = try UploadFileTracker(db: database, uploadObjectTrackerId: 2, status: .notStarted, fileUUID: UUID(), mimeType: .text, fileVersion: 11, localURL: URL(fileURLWithPath: "Foobly"), goneReason: .userRemoved, uploadCopy: false, checkSum: "Meebly", appMetaData: "Moo", uploadIndex: 1, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
        try entry2.insert()
        
        let count = try UploadFileTracker.numberRows(db: database, where:
            entry.id == UploadFileTracker.idField.description)
        
        XCTAssert(count == 1)
    }
}
