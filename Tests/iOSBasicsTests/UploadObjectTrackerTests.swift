import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared

class UploadObjectTrackerTests: XCTestCase, UploadConfigurable {
    // MARK: UploadConfigurable
    let uploadExpiryDuration: TimeInterval = 100

    var database: Connection!
    let fileGroupUUID = UUID()
    var entry:UploadObjectTracker!
    let message = "Message"
    
    override func setUpWithError() throws {
        database = try Connection(.inMemory)
        try UploadObjectTracker.createTable(db: database)
        try UploadFileTracker.createTable(db: database)
        try UploadFileTracker.allMigrations(configuration: self, db: database)
        
        entry = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID, v0Upload: true, batchUUID: UUID(), batchExpiryInterval: 100, pushNotificationMessage: message)
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func assertContentsCorrect(entry1: UploadObjectTracker, entry2: UploadObjectTracker) {
        XCTAssert(entry1.fileGroupUUID == entry2.fileGroupUUID)
    }
    
    func testDoubleCreateTable() throws {
        try UploadObjectTracker.createTable(db: database)
    }
    
    func testInsertIntoTable() throws {
        try entry.insert()
    }
    
    func testFilterWhenRowNotFound() throws {
        var count = 0
        try UploadObjectTracker.fetch(db: database,
            where: fileGroupUUID == UploadObjectTracker.fileGroupUUIDField.description) { row in
            count += 1
        }
        
        XCTAssert(count == 0)
    }
    
    func testFilterWhenRowFound() throws {
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
        try entry.insert()
        
        // Second entry-- to have a different fileGroupUUID, the primary key.
        let entry2 = try UploadObjectTracker(db: database, fileGroupUUID: UUID(), v0Upload: false, batchUUID: UUID(), batchExpiryInterval: 100, pushNotificationMessage: message)

        try entry2.insert()

        var count = 0
        try UploadObjectTracker.fetch(db: database) { row in
            count += 1
        }
        
        XCTAssert(count == 2)
    }
    
    func testUpdate() throws {
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
        let fileGroupUUID = UUID()

        let objectTracker = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID, v0Upload: true, batchUUID: UUID(), batchExpiryInterval: 100,  deferredUploadId: nil, pushNotificationMessage: message)
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
            fileTracker = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTrackerId, status: .uploaded, fileUUID: UUID(), mimeType: .text, fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil, appMetaData: nil, uploadIndex: 0, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
            try fileTracker.insert()
            
        case .oneOfTwoFilesMatching:
            let fileTracker2 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTrackerId, status: .uploading, fileUUID: UUID(), mimeType: .text, fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil, appMetaData: nil, uploadIndex: 1, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
            try fileTracker2.insert()
        }
        
        let results = try UploadObjectTracker.uploadsMatching(filePredicate: {$0.status == .uploaded}, scope: .all, db: database)
        
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
        let results = try UploadObjectTracker.uploadsMatching(filePredicate: {$0.status == .uploaded}, scope: .all, db: database)
        XCTAssert(results.count == 0)
    }

    func testAnyUploadsWithNoObjectsWorks() throws {
        let fileGroupUUID = UUID()
        
        let result = try UploadObjectTracker.uploadsMatching(filePredicate: {$0.status == .uploaded}, scope: .any, whereObjects: UploadObjectTracker.fileGroupUUIDField.description == fileGroupUUID, db: database)
        XCTAssert(result.count == 0)
    }
    
    func testAnyUploadsWithOneObjectNoneMatchingWorks() throws {
        let fileGroupUUID = UUID()

        let objectTracker = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID, v0Upload: true, batchUUID: UUID(), batchExpiryInterval: 100,  deferredUploadId: nil, pushNotificationMessage: message)
        try objectTracker.insert()
        
        let fileTracker = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker.id, status: .uploading, fileUUID: UUID(), mimeType: .text, fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil, appMetaData: nil, uploadIndex: 0, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
        try fileTracker.insert()

        let result = try UploadObjectTracker.uploadsMatching(filePredicate: {$0.status == .uploaded}, scope: .any, whereObjects: UploadObjectTracker.fileGroupUUIDField.description == fileGroupUUID, db: database)
        
        XCTAssert(result.count == 0)
    }
    
    func testAnyUploadsWithOneObjectOneOfOneMatchingWorks() throws {
        let fileGroupUUID = UUID()

        let objectTracker = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID, v0Upload: true, batchUUID: UUID(), batchExpiryInterval: 100, deferredUploadId: nil, pushNotificationMessage: message)
        try objectTracker.insert()
        
        let fileTracker = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker.id, status: .uploading, fileUUID: UUID(), mimeType: .text, fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil, appMetaData: nil, uploadIndex: 0, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
        try fileTracker.insert()
        
        let result = try UploadObjectTracker.uploadsMatching(filePredicate: {$0.status == .uploading}, scope: .any, whereObjects: UploadObjectTracker.fileGroupUUIDField.description == fileGroupUUID, db: database)
        XCTAssert(result.count == 1)
    }
    
    func testAnyUploadsWithOneObjectOneOfTwoMatchingWorks() throws {
        let fileGroupUUID = UUID()

        let objectTracker = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID, v0Upload: true, batchUUID: UUID(), batchExpiryInterval: 100,  deferredUploadId: nil, pushNotificationMessage: message)
        try objectTracker.insert()
        
        let fileTracker1 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker.id, status: .uploading, fileUUID: UUID(), mimeType: .text, fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil, appMetaData: nil, uploadIndex: 0, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
        try fileTracker1.insert()
        
        let fileTracker2 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker.id, status: .uploaded, fileUUID: UUID(), mimeType: .text, fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil, appMetaData: nil, uploadIndex: 0, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
        try fileTracker2.insert()

        let result = try UploadObjectTracker.uploadsMatching(filePredicate: {$0.status == .uploading}, scope: .any, whereObjects: UploadObjectTracker.fileGroupUUIDField.description == fileGroupUUID, db: database)
        XCTAssert(result.count == 1)
    }
    
    func testAnyUploadsWithOneObjectTwoOfTwoMatchingWorks() throws {
        let fileGroupUUID = UUID()
        
        let objectTracker = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID, v0Upload: true, batchUUID: UUID(), batchExpiryInterval: 100,  deferredUploadId: nil, pushNotificationMessage: message)
        try objectTracker.insert()
        
        let fileTracker1 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker.id, status: .uploading, fileUUID: UUID(), mimeType: .text, fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil, appMetaData: nil, uploadIndex: 0, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
        try fileTracker1.insert()
        
        let fileTracker2 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker.id, status: .uploading, fileUUID: UUID(), mimeType: .text, fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil, appMetaData: nil, uploadIndex: 0, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
        try fileTracker2.insert()

        let result = try UploadObjectTracker.uploadsMatching(filePredicate: {$0.status == .uploading}, scope: .any, whereObjects: UploadObjectTracker.fileGroupUUIDField.description == fileGroupUUID, db: database)
        XCTAssert(result.count == 1)
    }
    
    func testGetSharingGroup() throws {
        // There has to be a DirectoryObjectEntry for the UploadObjectTracker

        try DirectoryObjectEntry.createTable(db: database)

        let sharingGroupUUID = UUID()
        let fileGroupUUID = UUID()

        let uot = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID, v0Upload: true, batchUUID: UUID(), batchExpiryInterval: 100, deferredUploadId: nil, pushNotificationMessage: message)
        try uot.insert()

        let doe = try DirectoryObjectEntry(db: database, objectType: "Foobar2", fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, cloudStorageType: .Dropbox, deletedLocally: false, deletedOnServer: false)
        try doe.insert()
        
        let sharingGroup2 = try uot.getSharingGroup()
        
        XCTAssert(sharingGroupUUID == sharingGroup2)
    }
    
    // MARK: toBeStartedNext
    
    func testNoneToBeStartedBecauseNoTrackers() throws {
        let result = try UploadObjectTracker.toBeStartedNext(db: database)
        XCTAssert(result.count == 0)
    }
    
    // When there are only existing .uploading trackers for objects, none need to be started.
    func testNoneToBeStartedWithUploadingTrackers() throws {
        let fileGroupUUID = UUID()
        
        let objectTracker = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID, v0Upload: true, batchUUID: UUID(), batchExpiryInterval: 100,  deferredUploadId: nil, pushNotificationMessage: message)
        try objectTracker.insert()
        
        let fileTracker1 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker.id, status: .uploading, fileUUID: UUID(), mimeType: .text, fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil, appMetaData: nil, uploadIndex: 0, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
        try fileTracker1.insert()
        
        let result = try UploadObjectTracker.toBeStartedNext(db: database)
        XCTAssert(result.count == 0)
    }
    
    func testNoneToBeStartedWithUploadedTrackers() throws {
        let fileGroupUUID = UUID()
        
        let objectTracker = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID, v0Upload: true, batchUUID: UUID(), batchExpiryInterval: 100,  deferredUploadId: nil, pushNotificationMessage: message)
        try objectTracker.insert()
        
        let fileTracker1 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker.id, status: .uploaded, fileUUID: UUID(), mimeType: .text, fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil, appMetaData: nil, uploadIndex: 0, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
        try fileTracker1.insert()
        
        let result = try UploadObjectTracker.toBeStartedNext(db: database)
        XCTAssert(result.count == 0)
    }
    
    func testOneToBeStartedV0() throws {
        let fileGroupUUID = UUID()
        
        let objectTracker = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID, v0Upload: true, batchUUID: UUID(), batchExpiryInterval: 100,  deferredUploadId: nil, pushNotificationMessage: message)
        try objectTracker.insert()
        
        let fileTracker1 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker.id, status: .notStarted, fileUUID: UUID(), mimeType: .text, fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil, appMetaData: nil, uploadIndex: 0, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
        try fileTracker1.insert()
        
        let result = try UploadObjectTracker.toBeStartedNext(db: database)
        XCTAssert(result.count == 1)
    }
    
   func testOneToBeStartedVN() throws {
        let fileGroupUUID = UUID()
        
        let objectTracker = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID, v0Upload: false, batchUUID: UUID(), batchExpiryInterval: 100,  deferredUploadId: nil, pushNotificationMessage: message)
        try objectTracker.insert()
        
        let fileTracker1 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker.id, status: .notStarted, fileUUID: UUID(), mimeType: .text, fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil, appMetaData: nil, uploadIndex: 0, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
        try fileTracker1.insert()
        
        let result = try UploadObjectTracker.toBeStartedNext(db: database)
        XCTAssert(result.count == 1)
    }
    
    func testMultipleReadyToBeStartedV0() throws {
        let fileGroupUUID = UUID()
        
        let objectTracker1 = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID, v0Upload: true, batchUUID: UUID(), batchExpiryInterval: 100,  deferredUploadId: nil, pushNotificationMessage: message)
        try objectTracker1.insert()
        
        let fileTracker1 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker1.id, status: .notStarted, fileUUID: UUID(), mimeType: .text, fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil, appMetaData: nil, uploadIndex: 0, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
        try fileTracker1.insert()
        
        let objectTracker2 = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID, v0Upload: true, batchUUID: UUID(), batchExpiryInterval: 100,  deferredUploadId: nil, pushNotificationMessage: message)
        try objectTracker2.insert()
        
        let fileTracker2 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker2.id, status: .notStarted, fileUUID: UUID(), mimeType: .text, fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil, appMetaData: nil, uploadIndex: 0, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
        try fileTracker2.insert()
        
        let result = try UploadObjectTracker.toBeStartedNext(db: database)
        XCTAssert(result.count == 1)
    }
    
    func testMultipleReadyToBeStartedVN() throws {
        let fileGroupUUID = UUID()
        
        let objectTracker1 = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID, v0Upload: false, batchUUID: UUID(), batchExpiryInterval: 100,  deferredUploadId: nil, pushNotificationMessage: message)
        try objectTracker1.insert()
        
        let fileTracker1 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker1.id, status: .notStarted, fileUUID: UUID(), mimeType: .text, fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil, appMetaData: nil, uploadIndex: 0, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
        try fileTracker1.insert()
        
        let objectTracker2 = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID, v0Upload: false, batchUUID: UUID(), batchExpiryInterval: 100,  deferredUploadId: nil, pushNotificationMessage: message)
        try objectTracker2.insert()
        
        let fileTracker2 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker2.id, status: .notStarted, fileUUID: UUID(), mimeType: .text, fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil, appMetaData: nil, uploadIndex: 0, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
        try fileTracker2.insert()
        
        let result = try UploadObjectTracker.toBeStartedNext(db: database)
        XCTAssert(result.count == 1)
    }
    
    func testMultipleReadyToBeStartedBothV0AndVN() throws {
        let fileGroupUUID = UUID()
        
        let objectTracker1 = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID, v0Upload: true, batchUUID: UUID(), batchExpiryInterval: 100,  deferredUploadId: nil, pushNotificationMessage: message)
        try objectTracker1.insert()
        
        let fileTracker1 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker1.id, status: .notStarted, fileUUID: UUID(), mimeType: .text, fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil, appMetaData: nil, uploadIndex: 0, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
        try fileTracker1.insert()
        
        let objectTracker2 = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID, v0Upload: false, batchUUID: UUID(), batchExpiryInterval: 100,  deferredUploadId: nil, pushNotificationMessage: message)
        try objectTracker2.insert()
        
        let fileTracker2 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker2.id, status: .notStarted, fileUUID: UUID(), mimeType: .text, fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil, appMetaData: nil, uploadIndex: 0, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
        try fileTracker2.insert()
        
        let result = try UploadObjectTracker.toBeStartedNext(db: database)
        guard result.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(result[0].object.v0Upload == true)
    }
    
    func testMultipleDifferentFileGroupsReadyToBeStarted() throws {
        let fileGroupUUID1 = UUID()
        let fileGroupUUID2 = UUID()
        
        let objectTracker1 = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID1, v0Upload: true, batchUUID: UUID(), batchExpiryInterval: 100,  deferredUploadId: nil, pushNotificationMessage: message)
        try objectTracker1.insert()
        
        let fileTracker1 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker1.id, status: .notStarted, fileUUID: UUID(), mimeType: .text, fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil, appMetaData: nil, uploadIndex: 0, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
        try fileTracker1.insert()
        
        let objectTracker2 = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID2, v0Upload: false, batchUUID: UUID(), batchExpiryInterval: 100,  deferredUploadId: nil, pushNotificationMessage: message)
        try objectTracker2.insert()
        
        let fileTracker2 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker2.id, status: .notStarted, fileUUID: UUID(), mimeType: .text, fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil, appMetaData: nil, uploadIndex: 0, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
        try fileTracker2.insert()
        
        let result = try UploadObjectTracker.toBeStartedNext(db: database)
        guard result.count == 2 else {
            XCTFail()
            return
        }
        
        let result1 = result.filter {$0.object.fileGroupUUID == fileGroupUUID1}
        XCTAssert(result1.count == 1)
        let result2 = result.filter {$0.object.fileGroupUUID == fileGroupUUID2}
        XCTAssert(result2.count == 1)
    }
    
    func testNumberFileGroupsUploading_noUploads() throws {
        let number = try UploadObjectTracker.numberFileGroupsUploading(db: database)
        XCTAssert(number == 0)
    }
    
    func testNumberFileGroupsUploading_oneUploading() throws {
        let fileGroupUUID1 = UUID()
        
        let objectTracker1 = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID1, v0Upload: true, batchUUID: UUID(), batchExpiryInterval: 100,  deferredUploadId: nil, pushNotificationMessage: message)
        try objectTracker1.insert()
        
        let fileTracker1 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker1.id, status: .uploading, fileUUID: UUID(), mimeType: .text, fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil, appMetaData: nil, uploadIndex: 0, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
        try fileTracker1.insert()
        
        let number = try UploadObjectTracker.numberFileGroupsUploading(db: database)
        XCTAssert(number == 1)
    }
    
    func testNumberFileGroupsUploading_oneUploading_twoFiles() throws {
        let fileGroupUUID1 = UUID()
        
        let objectTracker1 = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID1, v0Upload: true, batchUUID: UUID(), batchExpiryInterval: 100,  deferredUploadId: nil, pushNotificationMessage: message)
        try objectTracker1.insert()
        
        let fileTracker1 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker1.id, status: .uploading, fileUUID: UUID(), mimeType: .text, fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil, appMetaData: nil, uploadIndex: 0, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
        try fileTracker1.insert()
        
        let fileTracker2 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker1.id, status: .uploading, fileUUID: UUID(), mimeType: .text, fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil, appMetaData: nil, uploadIndex: 0, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
        try fileTracker2.insert()
        
        let number = try UploadObjectTracker.numberFileGroupsUploading(db: database)
        XCTAssert(number == 1)
    }
    
    func testNumberFileGroupsUploading_oneTrackerNoneUploading() throws {
        let fileGroupUUID1 = UUID()
        
        let objectTracker1 = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID1, v0Upload: true, batchUUID: UUID(), batchExpiryInterval: 100,  deferredUploadId: nil, pushNotificationMessage: message)
        try objectTracker1.insert()
        
        let fileTracker1 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker1.id, status: .notStarted, fileUUID: UUID(), mimeType: .text, fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil, appMetaData: nil, uploadIndex: 0, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
        try fileTracker1.insert()
        
        let number = try UploadObjectTracker.numberFileGroupsUploading(db: database)
        XCTAssert(number == 0)
    }
    
    func testNumberFileGroupsUploading_twoUploading() throws {
        let fileGroupUUID1 = UUID()
        let fileGroupUUID2 = UUID()
        
        let objectTracker1 = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID1, v0Upload: true, batchUUID: UUID(), batchExpiryInterval: 100,  deferredUploadId: nil, pushNotificationMessage: message)
        try objectTracker1.insert()
        
        let fileTracker1 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker1.id, status: .uploading, fileUUID: UUID(), mimeType: .text, fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil, appMetaData: nil, uploadIndex: 0, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
        try fileTracker1.insert()
        
        let objectTracker2 = try UploadObjectTracker(db: database, fileGroupUUID: fileGroupUUID2, v0Upload: true, batchUUID: UUID(), batchExpiryInterval: 100,  deferredUploadId: nil, pushNotificationMessage: message)
        try objectTracker2.insert()
        
        let fileTracker2 = try UploadFileTracker(db: database, uploadObjectTrackerId: objectTracker2.id, status: .uploading, fileUUID: UUID(), mimeType: .text, fileVersion: 0, localURL: nil, goneReason: nil, uploadCopy: false, checkSum: nil, appMetaData: nil, uploadIndex: 0, uploadCount: 1, informAllButSelf: nil, expiry: Date() + 100)
        try fileTracker2.insert()
        
        let number = try UploadObjectTracker.numberFileGroupsUploading(db: database)
        XCTAssert(number == 2)
    }
}
