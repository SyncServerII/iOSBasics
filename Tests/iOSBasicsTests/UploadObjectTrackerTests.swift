import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared

class UploadObjectTrackerTests: XCTestCase {
    var database: Connection!
    let fileGroupUUID = UUID()
    var entry:UploadObjectTracker!
    
    override func setUpWithError() throws {
        set(logLevel: .trace)
        database = try Connection(.inMemory)
        entry = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID, v0Upload: true)
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func assertContentsCorrect(entry1: UploadObjectTracker, entry2: UploadObjectTracker) {
        XCTAssert(entry1.fileGroupUUID == entry2.fileGroupUUID)
    }

    func testCreateTable() throws {
        try UploadObjectTracker.createTable(db: database)
    }
    
    func testDoubleCreateTable() throws {
        try UploadObjectTracker.createTable(db: database)
        try UploadObjectTracker.createTable(db: database)
    }
    
    func testInsertIntoTable() throws {
        try UploadObjectTracker.createTable(db: database)
        try entry.insert()
    }
    
    func testFilterWhenRowNotFound() throws {
        try UploadObjectTracker.createTable(db: database)
        
        var count = 0
        try UploadObjectTracker.fetch(db: database,
            where: fileGroupUUID == UploadObjectTracker.fileGroupUUIDField.description) { row in
            count += 1
        }
        
        XCTAssert(count == 0)
    }
    
    func testFilterWhenRowFound() throws {
        try UploadObjectTracker.createTable(db: database)
        try entry.insert()
        
        var count = 0
        try UploadObjectTracker.fetch(db: database,
            where: fileGroupUUID == UploadObjectTracker.fileGroupUUIDField.description) { row in
            assertContentsCorrect(entry1: entry, entry2: row)
            count += 1
        }
        
        XCTAssert(count == 1)
    }
    
    func testFilterWhenTwoRowsFound() throws {
        try UploadObjectTracker.createTable(db: database)
        try entry.insert()
        
        // Second entry-- to have a different fileGroupUUID, the primary key.
        let entry2 = try UploadObjectTracker(db: database, fileGroupUUID: UUID(), v0Upload: false)

        try entry2.insert()

        var count = 0
        try UploadObjectTracker.fetch(db: database) { row in
            count += 1
        }
        
        XCTAssert(count == 2)
    }
    
    func testUpdate() throws {
        try UploadObjectTracker.createTable(db: database)
        try entry.insert()
                
        let replacement = UUID()
        
        entry = try entry.update(setters:
            UploadObjectTracker.fileGroupUUIDField.description <- replacement
        )
                
        var count = 0
        try UploadObjectTracker.fetch(db: database,
            where: replacement == UploadObjectTracker.fileGroupUUIDField.description) { row in
            XCTAssert(row.fileGroupUUID == replacement, "\(row.fileGroupUUID)")
            count += 1
        }
        
        XCTAssert(entry.fileGroupUUID == replacement)
        
        XCTAssert(count == 1)
    }
    
    func testDelete() throws {
        try UploadObjectTracker.createTable(db: database)
        try entry.insert()
        
        try entry.delete()
    }
     
     enum UploadsWithBasicTests {
        // Not really a valid expected case, but want to make sure it does something reasonable
        case noFiles
        
        case oneFile
        
        case oneOfTwoFilesMatching
     }
     
     func runUploadsWith(type: UploadsWithBasicTests) throws {
        try UploadObjectTracker.createTable(db: database)
        try UploadFileTracker.createTable(db: database)
        
        let fileGroupUUID = UUID()
        let objectTracker = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID, v0Upload: true, deferredUploadId: nil)
        try objectTracker.insert()
        
        guard let objectTrackerId = objectTracker.id else {
            XCTFail()
            return
        }
        
        var fileTracker:UploadFileTracker!
        
        switch type {
        case .noFiles:
            break
            
        case .oneFile:
            fileTracker = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTrackerId, status: .uploaded, fileUUID: UUID(), fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil)
            try fileTracker.insert()
            
        case .oneOfTwoFilesMatching:
            let fileTracker2 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTrackerId, status: .uploading, fileUUID: UUID(), fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil)
            try fileTracker2.insert()
        }
        
        let results = try UploadObjectTracker.allUploadsWith(status: .uploaded, db: database)

        switch type {
        case .noFiles:
            XCTAssert(results.count == 0)
            
        case .oneFile:
            guard results.count == 1 else {
                XCTFail()
                return
            }
            
            XCTAssert(results[0].object.fileGroupUUID == fileGroupUUID)
            guard results[0].files.count == 1 else {
                XCTFail()
                return
            }
            
            XCTAssert(results[0].files[0].fileUUID == fileTracker.fileUUID)
            
        case .oneOfTwoFilesMatching:
            XCTAssert(results.count == 0)
        }
    }
    
    func testUploadsWithObjectTrackerWithNoFiles() throws {
        try runUploadsWith(type: .noFiles)
    }

    func testUploadsWithObjectTrackerWithOneFile() throws {
        try runUploadsWith(type: .oneFile)
    }
    
    func testUploadsWithObjectTrackerWithOneOfTwoFilesMatching() throws {
        try runUploadsWith(type: .oneOfTwoFilesMatching)
    }
    
    func testUploadsWithWithNothing() throws {
        try UploadObjectTracker.createTable(db: database)
        try UploadFileTracker.createTable(db: database)
        let results = try UploadObjectTracker.allUploadsWith(status: .uploaded, db: database)
        XCTAssert(results.count == 0)
    }
    
    func testAnyUploadsWithNoObjectsWorks() throws {
        try UploadObjectTracker.createTable(db: database)
        try UploadFileTracker.createTable(db: database)
        let fileGroupUUID = UUID()
        
        guard !(try UploadObjectTracker.anyUploadsWith(status: .uploaded, fileGroupUUID: fileGroupUUID, db: database)) else {
            XCTFail()
            return
        }
    }
    
    func testAnyUploadsWithOneObjectNoneMatchingWorks() throws {
        try UploadObjectTracker.createTable(db: database)
        try UploadFileTracker.createTable(db: database)
        let fileGroupUUID = UUID()
        
        let objectTracker = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID, v0Upload: true, deferredUploadId: nil)
        try objectTracker.insert()
        
        let fileTracker = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker.id, status: .uploading, fileUUID: UUID(), fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil)
        try fileTracker.insert()
        
        guard !(try UploadObjectTracker.anyUploadsWith(status: .uploaded, fileGroupUUID: fileGroupUUID, db: database)) else {
            XCTFail()
            return
        }
    }
    
    func testAnyUploadsWithOneObjectOneOfOneMatchingWorks() throws {
        try UploadObjectTracker.createTable(db: database)
        try UploadFileTracker.createTable(db: database)
        let fileGroupUUID = UUID()
        
        let objectTracker = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID, v0Upload: true, deferredUploadId: nil)
        try objectTracker.insert()
        
        let fileTracker = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker.id, status: .uploading, fileUUID: UUID(), fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil)
        try fileTracker.insert()
        
        guard try UploadObjectTracker.anyUploadsWith(status: .uploading, fileGroupUUID: fileGroupUUID, db: database) else {
            XCTFail()
            return
        }
    }
    
    func testAnyUploadsWithOneObjectOneOfTwoMatchingWorks() throws {
        try UploadObjectTracker.createTable(db: database)
        try UploadFileTracker.createTable(db: database)
        let fileGroupUUID = UUID()
        
        let objectTracker = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID, v0Upload: true, deferredUploadId: nil)
        try objectTracker.insert()
        
        let fileTracker1 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker.id, status: .uploading, fileUUID: UUID(), fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil)
        try fileTracker1.insert()
        
        let fileTracker2 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker.id, status: .uploaded, fileUUID: UUID(), fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil)
        try fileTracker2.insert()
        
        guard try UploadObjectTracker.anyUploadsWith(status: .uploading, fileGroupUUID: fileGroupUUID, db: database) else {
            XCTFail()
            return
        }
    }
    
    func testAnyUploadsWithOneObjectTwoOfTwoMatchingWorks() throws {
        try UploadObjectTracker.createTable(db: database)
        try UploadFileTracker.createTable(db: database)
        let fileGroupUUID = UUID()
        
        let objectTracker = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID, v0Upload: true, deferredUploadId: nil)
        try objectTracker.insert()
        
        let fileTracker1 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker.id, status: .uploading, fileUUID: UUID(), fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil)
        try fileTracker1.insert()
        
        let fileTracker2 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker.id, status: .uploading, fileUUID: UUID(), fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil)
        try fileTracker2.insert()
        
        guard try UploadObjectTracker.anyUploadsWith(status: .uploading, fileGroupUUID: fileGroupUUID, db: database) else {
            XCTFail()
            return
        }
    }
}
