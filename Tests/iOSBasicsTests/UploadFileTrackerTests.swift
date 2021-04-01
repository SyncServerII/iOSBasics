import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared

class UploadFileTrackerTests: XCTestCase {
    var database: Connection!
    let fileUUID = UUID()
    var entry:UploadFileTracker!
    
    override func setUpWithError() throws {
        database = try Connection(.inMemory)
        entry = try UploadFileTracker(db: database, uploadObjectTrackerId: 2, status: .notStarted, fileUUID: fileUUID, mimeType: .text, fileVersion: 11, localURL: URL(fileURLWithPath: "Foobly"), goneReason: .userRemoved, uploadCopy: false, checkSum: "Meebly", appMetaData: "Foo", uploadIndex: 0, uploadCount: 1)
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func assertContentsCorrect(entry1: UploadFileTracker, entry2: UploadFileTracker) {
        XCTAssert(entry1.status == entry2.status)
        XCTAssert(entry1.fileUUID == entry2.fileUUID)
        XCTAssert(entry1.fileVersion == entry2.fileVersion)
        XCTAssert(entry1.localURL?.path == entry2.localURL?.path)
        XCTAssert(entry1.goneReason == entry2.goneReason)
        XCTAssert(entry1.uploadCopy == entry2.uploadCopy)
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
            where: fileUUID == UploadFileTracker.fileUUIDField.description) { row in
            count += 1
        }
        
        XCTAssert(count == 0)
    }
    
    func testFilterWhenRowFound() throws {
        try UploadFileTracker.createTable(db: database)
        try entry.insert()
        
        var count = 0
        try UploadFileTracker.fetch(db: database,
            where: fileUUID == UploadFileTracker.fileUUIDField.description) { row in
            assertContentsCorrect(entry1: entry, entry2: row)
            count += 1
        }
        
        XCTAssert(count == 1)
    }
    
    func testFilterWhenTwoRowsFound() throws {
        try UploadFileTracker.createTable(db: database)
        try entry.insert()
        
        // Second entry-- to have a different fileUUID, the primary key.
        let entry2 = try UploadFileTracker(db: database, uploadObjectTrackerId: 2, status: .notStarted, fileUUID: UUID(), mimeType: .text, fileVersion: 11, localURL: URL(fileURLWithPath: "Foobly"), goneReason: .userRemoved, uploadCopy: false, checkSum: "Meebly", appMetaData: nil, uploadIndex: 1, uploadCount: 1)

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
            UploadFileTracker.fileUUIDField.description <- replacement
        )
                
        var count = 0
        try UploadFileTracker.fetch(db: database,
            where: replacement == UploadFileTracker.fileUUIDField.description) { row in
            XCTAssert(row.fileUUID == replacement, "\(row.fileUUID)")
            count += 1
        }
        
        XCTAssert(entry.fileUUID == replacement)
        
        XCTAssert(count == 1)
    }
    
    func testDelete() throws {
        try UploadFileTracker.createTable(db: database)
        try entry.insert()
        
        try entry.delete()
    }
    
    func testChangeStatusOfExactlyOneRecord() throws {
        try UploadFileTracker.createTable(db: database)
        
        let originalStatus: UploadFileTracker.Status = .notStarted
        
        let e1 = try UploadFileTracker(db: database, uploadObjectTrackerId: 1, status: originalStatus, fileUUID: fileUUID, mimeType: .text, fileVersion: 11, localURL: URL(fileURLWithPath: "Foobly"), goneReason: .userRemoved, uploadCopy: false, checkSum: "Meebly", appMetaData: "moo", uploadIndex: 1, uploadCount: 1)
        try e1.insert()
        
        let e2 = try UploadFileTracker(db: database, uploadObjectTrackerId: 2, status: originalStatus, fileUUID: fileUUID, mimeType: .text, fileVersion: 11, localURL: URL(fileURLWithPath: "Foobly"), goneReason: .userRemoved, uploadCopy: false, checkSum: "Meebly", appMetaData: "bloo", uploadIndex: 1, uploadCount: 1)
        try e2.insert()
        
        try e1.update(setters:
            UploadFileTracker.statusField.description <- .uploaded)
            
        guard let e2Copy = try UploadFileTracker.fetchSingleRow(db: database, where: e2.id == UploadFileTracker.idField.description) else {
            XCTFail()
            return
        }
        
        XCTAssert(e2Copy.status == originalStatus, "\(e2Copy.status)")
    }
    
    func testRetrievedMimeTypeIsSame() throws {
        try UploadFileTracker.createTable(db: database)
                
        let mimeType:MimeType = .text
        let e1 = try UploadFileTracker(db: database, uploadObjectTrackerId: 1, status: .notStarted, fileUUID: fileUUID, mimeType: mimeType, fileVersion: 11, localURL: URL(fileURLWithPath: "Foobly"), goneReason: .userRemoved, uploadCopy: false, checkSum: "Meebly", appMetaData: "moo", uploadIndex: 1, uploadCount: 1)
        try e1.insert()
        
        let result = try UploadFileTracker.fetch(db: database,
            where: e1.fileUUID == UploadFileTracker.fileUUIDField.description)
            
        guard result.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(result[0].mimeType == mimeType)
    }
}
