import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared

class UploadDeletionTrackerTests: XCTestCase {
    var database: Connection!
    let fileUUID = UUID()
    var entry:UploadDeletionTracker!
    let message = "Message"
    
    override func setUpWithError() throws {
        set(logLevel: .trace)
        database = try Connection(.inMemory)
        entry = try UploadDeletionTracker(db: database, uuid: fileUUID, deletionType: .fileUUID, deferredUploadId: 0, status: .waitingForDeferredDeletion, pushNotificationMessage: message)
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func assertContentsCorrect(entry1: UploadDeletionTracker, entry2: UploadDeletionTracker) {
        XCTAssert(entry1.status == entry2.status)
        XCTAssert(entry1.uuid == entry2.uuid)
        XCTAssert(entry1.deferredUploadId == entry2.deferredUploadId)
        XCTAssert(entry1.deletionType == entry2.deletionType)
    }

    func testCreateTable() throws {
        try UploadDeletionTracker.createTable(db: database)
    }
    
    func testDoubleCreateTable() throws {
        try UploadDeletionTracker.createTable(db: database)
        try UploadDeletionTracker.createTable(db: database)
    }
    
    func testInsertIntoTable() throws {
        try UploadDeletionTracker.createTable(db: database)
        try entry.insert()
    }
    
    func testFilterWhenRowNotFound() throws {
        try UploadDeletionTracker.createTable(db: database)
        
        var count = 0
        try UploadDeletionTracker.fetch(db: database,
            where: fileUUID == UploadDeletionTracker.uuidField.description) { row in
            count += 1
        }
        
        XCTAssert(count == 0)
    }
    
    func testFilterWhenRowFound() throws {
        try UploadDeletionTracker.createTable(db: database)
        try entry.insert()
        
        var count = 0
        try UploadDeletionTracker.fetch(db: database,
            where: fileUUID == UploadDeletionTracker.uuidField.description) { row in
            assertContentsCorrect(entry1: entry, entry2: row)
            count += 1
        }
        
        XCTAssert(count == 1, "\(count)")
    }
    
    func testFilterWhenTwoRowsFound() throws {
        try UploadDeletionTracker.createTable(db: database)
        try entry.insert()
        
        // Second entry-- to have a different fileUUID, the primary key.
        let entry2 = try UploadDeletionTracker(db: database, uuid: UUID(), deletionType: .fileUUID, deferredUploadId: 0, status: .waitingForDeferredDeletion, pushNotificationMessage: message)

        try entry2.insert()

        var count = 0
        try UploadDeletionTracker.fetch(db: database) { row in
            count += 1
        }
        
        XCTAssert(count == 2)
    }
    
    func testUpdate() throws {
        try UploadDeletionTracker.createTable(db: database)
        try entry.insert()
                
        let replacement = UUID()
        
        entry = try entry.update(setters:
            UploadDeletionTracker.uuidField.description <- replacement
        )
                
        var count = 0
        try UploadDeletionTracker.fetch(db: database,
            where: replacement == UploadDeletionTracker.uuidField.description) { row in
            XCTAssert(row.uuid == replacement, "\(row.uuid)")
            count += 1
        }
        
        XCTAssert(entry.uuid == replacement)
        
        XCTAssert(count == 1)
    }
    
    func testDelete() throws {
        try UploadDeletionTracker.createTable(db: database)
        try entry.insert()
        
        try entry.delete()
    }
    
    func testChangeStatusOfExactlyOneRecord() throws {
        try UploadDeletionTracker.createTable(db: database)
        
        let originalStatus: UploadDeletionTracker.Status = .notStarted
        
        let e1 = try UploadDeletionTracker(db: database, uuid: UUID(), deletionType: .fileUUID, deferredUploadId: 0, status: originalStatus, pushNotificationMessage: message)
        try e1.insert()
        
        let e2 = try UploadDeletionTracker(db: database, uuid: UUID(), deletionType: .fileUUID, deferredUploadId: 0, status: originalStatus, pushNotificationMessage: message)
        try e2.insert()
        
        try e1.update(setters:
            UploadDeletionTracker.statusField.description <- .deleting)
            
        guard let e2Copy = try UploadDeletionTracker.fetchSingleRow(db: database, where: e2.id == UploadDeletionTracker.idField.description) else {
            XCTFail()
            return
        }
        
        XCTAssert(e2Copy.status == originalStatus, "\(e2Copy.status)")
    }
    
    func testGetSharingGroup() throws {
        // There has to be a DirectoryObjectEntry for the UploadDeletionTracker

        try UploadDeletionTracker.createTable(db: database)
        try DirectoryObjectEntry.createTable(db: database)

        let sharingGroupUUID = UUID()
        let fileGroupUUID = UUID()

        let udt = try UploadDeletionTracker(db: database, uuid: fileGroupUUID, deletionType: .fileGroupUUID, deferredUploadId: 0, status: .deleting, pushNotificationMessage: message)
        try udt.insert()

        let doe = try DirectoryObjectEntry(db: database, objectType: "Foobar2", fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, cloudStorageType: .Dropbox, deletedLocally: false, deletedOnServer: false)
        try doe.insert()
        
        let sharingGroup2 = try udt.getSharingGroup()
        
        XCTAssert(sharingGroupUUID == sharingGroup2)
    }
}
