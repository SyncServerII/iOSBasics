import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
@testable import TestsCommon

class UploadFileTrackerTests: XCTestCase {
    var database: Connection!
    let sharingGroupUUID = UUID()
    var entry:UploadFileTracker!
    
    override func setUpWithError() throws {
        database = try Connection(.inMemory)
        entry = try UploadFileTracker(db: database, status: .notStarted, sharingGroupUUID: sharingGroupUUID, appMetaData: "Foobly", fileGroupUUID: UUID(), fileUUID: UUID(), fileVersion: 11, localURL: URL(fileURLWithPath: "Foobly"), mimeType: .text, goneReason: .userRemoved, uploadCopy: false, uploadUndeletion: true, checkSum: "Meebly")
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func assertContentsCorrect(entry1: UploadFileTracker, entry2: UploadFileTracker) {
        XCTAssert(entry1.status == entry2.status)
        XCTAssert(entry1.sharingGroupUUID == entry2.sharingGroupUUID)
        XCTAssert(entry1.appMetaData == entry2.appMetaData)
        XCTAssert(entry1.fileGroupUUID == entry2.fileGroupUUID)
        XCTAssert(entry1.fileUUID == entry2.fileUUID)
        XCTAssert(entry1.fileVersion == entry2.fileVersion)
        XCTAssert(entry1.localURL?.path == entry2.localURL?.path)
        XCTAssert(entry1.mimeType == entry2.mimeType)
        XCTAssert(entry1.goneReason == entry2.goneReason)
        XCTAssert(entry1.uploadCopy == entry2.uploadCopy)
        XCTAssert(entry1.uploadUndeletion == entry2.uploadUndeletion)
        XCTAssert(entry1.checkSum == entry2.checkSum)
    }

    func testCreateTable() throws {
        try UploadFileTracker.createTable(db: database)
    }
    
    func testDoubleCreateTable() throws {
        try UploadFileTracker.createTable(db: database)
        try UploadFileTracker.createTable(db: database)
    }
    
    func testInsertIntoTable() throws {
        try UploadFileTracker.createTable(db: database)
        try entry.insert()
    }
    
    func testFilterWhenRowNotFound() throws {
        try UploadFileTracker.createTable(db: database)
        
        var count = 0
        try UploadFileTracker.fetch(db: database,
            where: sharingGroupUUID == UploadFileTracker.sharingGroupUUIDField.description) { row in
            count += 1
        }
        
        XCTAssert(count == 0)
    }
    
    func testFilterWhenRowFound() throws {
        try UploadFileTracker.createTable(db: database)
        try entry.insert()
        
        var count = 0
        try UploadFileTracker.fetch(db: database,
            where: sharingGroupUUID == UploadFileTracker.sharingGroupUUIDField.description) { row in
            assertContentsCorrect(entry1: entry, entry2: row)
            count += 1
        }
        
        XCTAssert(count == 1)
    }
    
    func testFilterWhenTwoRowsFound() throws {
        try UploadFileTracker.createTable(db: database)
        try entry.insert()
        
        // Second entry-- to have a different fileUUID, the primary key.
        let entry2 = try UploadFileTracker(db: database, status: .notStarted, sharingGroupUUID: sharingGroupUUID, appMetaData: "Foobly", fileGroupUUID: UUID(), fileUUID: UUID(), fileVersion: 11, localURL: URL(fileURLWithPath: "Foobly"), mimeType: .text, goneReason: .userRemoved, uploadCopy: false, uploadUndeletion: true, checkSum: "Meebly")

        try entry2.insert()

        var count = 0
        try UploadFileTracker.fetch(db: database) { row in
            count += 1
        }
        
        XCTAssert(count == 2)
    }
    
    func testUpdate() throws {
        try UploadFileTracker.createTable(db: database)
        try entry.insert()
                
        let replacement = UUID()
        
        entry = try entry.update(setters:
            UploadFileTracker.sharingGroupUUIDField.description <- replacement
        )
                
        var count = 0
        try UploadFileTracker.fetch(db: database,
            where: replacement == UploadFileTracker.sharingGroupUUIDField.description) { row in
            XCTAssert(row.sharingGroupUUID == replacement, "\(row.sharingGroupUUID)")
            count += 1
        }
        
        XCTAssert(entry.sharingGroupUUID == replacement)
        
        XCTAssert(count == 1)
    }
    
    func testDelete() throws {
        try UploadFileTracker.createTable(db: database)
        try entry.insert()
        
        try entry.delete()
    }
}
