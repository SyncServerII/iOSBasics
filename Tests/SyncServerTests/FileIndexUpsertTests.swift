// These tests are all synchronous, not hitting on the server.

import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
@testable import TestsCommon

class FileIndexUpsertTests: XCTestCase, Delegate, UserSetup {
    var api: ServerAPI!
    var handlers = DelegateHandlers()
    var fakeHelper:SignInServicesHelperFake!
    var deviceUUID: UUID!
    var syncServer: SyncServer!
    var database: Connection!
    var config:Configuration!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        handlers = DelegateHandlers()
        handlers.user = try dropboxUser()
        deviceUUID = UUID()
        database = try Connection(.inMemory)
        let hashingManager = HashingManager()
        let serverURL = URL(string: "http://fake.com")!
        config = Configuration(appGroupIdentifier: nil, serverURL: serverURL, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: "Fake", deviceUUID: deviceUUID, packageTests: true)
        fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, configuration: config, signIns: fakeSignIns)
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
    }

    override func tearDownWithError() throws {
    }

    func testEmptyFileIndexDoesNotFail() throws {
        try syncServer.upsert(fileIndex: [], sharingGroupUUID: UUID())
    }
    
    func createFileInfo(fileUUID: UUID, fileGroupUUID:UUID, sharingGroupUUID:UUID, mimeType: MimeType, deleted: Bool, fileVersion: FileVersionInt, cloudStorageType: CloudStorageType, objectType: String) -> FileInfo {
    
        let fileInfo = FileInfo()
        fileInfo.fileUUID = fileUUID.uuidString
        fileInfo.fileGroupUUID = fileGroupUUID.uuidString
        fileInfo.sharingGroupUUID = sharingGroupUUID.uuidString
        fileInfo.mimeType = mimeType.rawValue
        fileInfo.deleted = deleted
        fileInfo.fileVersion = fileVersion
        fileInfo.cloudStorageType = cloudStorageType.rawValue
        fileInfo.objectType = objectType
        
        return fileInfo
    }
    
    func runWithFileIndex(mismatchingSharingGroup: Bool) throws {
        let sharingGroupUUID = UUID()
        
        let fileInfoSharingGroupUUID: UUID
        if mismatchingSharingGroup {
            fileInfoSharingGroupUUID = UUID()
        }
        else {
            fileInfoSharingGroupUUID = sharingGroupUUID
        }
        
        let fileInfo = createFileInfo(fileUUID: UUID(), fileGroupUUID: UUID(), sharingGroupUUID: fileInfoSharingGroupUUID, mimeType: .text, deleted: true, fileVersion: 0, cloudStorageType: .Dropbox, objectType: "Foo")
        
        do {
            try syncServer.upsert(fileIndex: [fileInfo], sharingGroupUUID: sharingGroupUUID)
        } catch let error {
            if !mismatchingSharingGroup {
                XCTFail("\(error)")
            }
            return
        }
        
        if mismatchingSharingGroup {
            XCTFail()
        }
    }
    
    func testFileIndexWithMismatchingSharingGroupFails() throws {
        try runWithFileIndex(mismatchingSharingGroup: true)
    }
    
    func testFileIndexWithMatchingSharingGroupWorks() throws {
        try runWithFileIndex(mismatchingSharingGroup: false)
    }
    
    func testNewFileInfoAddsExpectedDatabaseRecords() throws {
        let sharingGroupUUID = UUID()

        let fileUUID = UUID()
        let fileGroupUUID = UUID()
        
        let fileInfo = createFileInfo(fileUUID: fileUUID, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, mimeType: .text, deleted: true, fileVersion: 0, cloudStorageType: .Dropbox, objectType: "Foo")
        
        try syncServer.upsert(fileIndex: [fileInfo], sharingGroupUUID: sharingGroupUUID)
        
        guard let directoryEntry = try DirectoryEntry.fetchSingleRow(db: database, where: DirectoryEntry.fileUUIDField.description == fileUUID) else {
            XCTFail()
            return
        }
        
        // Expect: DirectoryEntry, DeclaredFileModel, DeclaredObjectModel

        XCTAssert(directoryEntry.fileUUID.uuidString == fileInfo.fileUUID)
        XCTAssert(directoryEntry.fileGroupUUID == fileGroupUUID)
        XCTAssert(directoryEntry.sharingGroupUUID.uuidString == fileInfo.sharingGroupUUID)
        XCTAssert(directoryEntry.deletedLocally == fileInfo.deleted)
        XCTAssert(directoryEntry.deletedOnServer == fileInfo.deleted)
        XCTAssert(directoryEntry.serverFileVersion == fileInfo.fileVersion)
        XCTAssert(directoryEntry.fileVersion == nil)
        
        guard let declaredFile = try DeclaredFileModel.fetchSingleRow(db: database, where: DeclaredFileModel.uuidField.description == fileUUID) else {
            XCTFail()
            return
        }

        XCTAssert(declaredFile.uuid.uuidString == fileInfo.fileUUID)
        XCTAssert(declaredFile.mimeType.rawValue == fileInfo.mimeType)
        XCTAssert(declaredFile.fileGroupUUID == fileGroupUUID)
        XCTAssert(declaredFile.changeResolverName == fileInfo.changeResolverName)
        XCTAssert(declaredFile.appMetaData == fileInfo.appMetaData)

        guard let declaredObject = try DeclaredObjectModel.fetchSingleRow(db: database, where: DeclaredObjectModel.fileGroupUUIDField.description == fileGroupUUID) else {
            XCTFail()
            return
        }
        
        XCTAssert(declaredObject.fileGroupUUID == fileGroupUUID)
        XCTAssert(declaredObject.objectType == fileInfo.objectType)
        XCTAssert(declaredObject.fileGroupUUID == fileGroupUUID)
        XCTAssert(declaredObject.sharingGroupUUID == sharingGroupUUID)
    }
    
    func testKnownFileInfoDoesNotAddOrChangeDatabaseRecords() throws {
        let sharingGroupUUID = UUID()
        let fileUUID = UUID()
        let fileGroupUUID = UUID()
        
        let fileInfo = createFileInfo(fileUUID: fileUUID, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, mimeType: .text, deleted: true, fileVersion: 0, cloudStorageType: .Dropbox, objectType: "Foo")
        
        try syncServer.upsert(fileIndex: [fileInfo], sharingGroupUUID: sharingGroupUUID)
        
        guard let directoryEntry = try DirectoryEntry.fetchSingleRow(db: database, where: DirectoryEntry.fileUUIDField.description == fileUUID) else {
            XCTFail()
            return
        }
        
        guard let declaredFile = try DeclaredFileModel.fetchSingleRow(db: database, where: DeclaredFileModel.uuidField.description == fileUUID) else {
            XCTFail()
            return
        }

        guard let declaredObject = try DeclaredObjectModel.fetchSingleRow(db: database, where: DeclaredObjectModel.fileGroupUUIDField.description == fileGroupUUID) else {
            XCTFail()
            return
        }
        
        XCTAssert(try DirectoryEntry.numberRows(db: database) == 1)
        XCTAssert(try DeclaredObjectModel.numberRows(db: database) == 1)
        XCTAssert(try DeclaredFileModel.numberRows(db: database) == 1)
        
        // This simulates a second server `index` call for the same sharing group. It should not alter the database.
        try syncServer.upsert(fileIndex: [fileInfo], sharingGroupUUID: sharingGroupUUID)

        XCTAssert(try DirectoryEntry.numberRows(db: database) == 1)
        XCTAssert(try DeclaredObjectModel.numberRows(db: database) == 1)
        XCTAssert(try DeclaredFileModel.numberRows(db: database) == 1)
        
        guard let directoryEntry2 = try DirectoryEntry.fetchSingleRow(db: database, where: DirectoryEntry.fileUUIDField.description == fileUUID) else {
            XCTFail()
            return
        }
        
        XCTAssert(directoryEntry == directoryEntry2)
        
        guard let declaredFile2 = try DeclaredFileModel.fetchSingleRow(db: database, where: DeclaredFileModel.uuidField.description == fileUUID) else {
            XCTFail()
            return
        }
        
        XCTAssert(declaredFile == declaredFile2)
        
        guard let declaredObject2 = try DeclaredObjectModel.fetchSingleRow(db: database, where: DeclaredObjectModel.fileGroupUUIDField.description == fileGroupUUID) else {
            XCTFail()
            return
        }
        
        XCTAssert(declaredObject == declaredObject2)
    }
    
    func testKnownFileInfoWithValidUpdateChangesDatabaseRecord() throws {
        let sharingGroupUUID = UUID()
        let fileUUID = UUID()
        let fileGroupUUID = UUID()
        
        let fileInfo = createFileInfo(fileUUID: fileUUID, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, mimeType: .text, deleted: false, fileVersion: 0, cloudStorageType: .Dropbox, objectType: "Foo")
        
        try syncServer.upsert(fileIndex: [fileInfo], sharingGroupUUID: sharingGroupUUID)
        
        guard let directoryEntry = try DirectoryEntry.fetchSingleRow(db: database, where: DirectoryEntry.fileUUIDField.description == fileUUID) else {
            XCTFail()
            return
        }
        
        guard let declaredFile = try DeclaredFileModel.fetchSingleRow(db: database, where: DeclaredFileModel.uuidField.description == fileUUID) else {
            XCTFail()
            return
        }

        guard let declaredObject = try DeclaredObjectModel.fetchSingleRow(db: database, where: DeclaredObjectModel.fileGroupUUIDField.description == fileGroupUUID) else {
            XCTFail()
            return
        }
        
        XCTAssert(try DirectoryEntry.numberRows(db: database) == 1)
        XCTAssert(try DeclaredObjectModel.numberRows(db: database) == 1)
        XCTAssert(try DeclaredFileModel.numberRows(db: database) == 1)
        
        // This simulates a second server `index` call for the same sharing group. But, this time the fileInfo record has valid changes.
        fileInfo.deleted = true
        fileInfo.fileVersion = 1
        
        try syncServer.upsert(fileIndex: [fileInfo], sharingGroupUUID: sharingGroupUUID)

        XCTAssert(try DirectoryEntry.numberRows(db: database) == 1)
        XCTAssert(try DeclaredObjectModel.numberRows(db: database) == 1)
        XCTAssert(try DeclaredFileModel.numberRows(db: database) == 1)
        
        guard let directoryEntry2 = try DirectoryEntry.fetchSingleRow(db: database, where: DirectoryEntry.fileUUIDField.description == fileUUID) else {
            XCTFail()
            return
        }
        
        guard directoryEntry != directoryEntry2 else {
            XCTFail()
            return
        }
        
        XCTAssert(directoryEntry2.serverFileVersion == fileInfo.fileVersion)
        XCTAssert(directoryEntry2.fileVersion == nil)
        XCTAssert(directoryEntry2.deletedOnServer)
        XCTAssert(!directoryEntry2.deletedLocally)
        
        guard let declaredFile2 = try DeclaredFileModel.fetchSingleRow(db: database, where: DeclaredFileModel.uuidField.description == fileUUID) else {
            XCTFail()
            return
        }
        
        XCTAssert(declaredFile == declaredFile2)
        
        guard let declaredObject2 = try DeclaredObjectModel.fetchSingleRow(db: database, where: DeclaredObjectModel.fileGroupUUIDField.description == fileGroupUUID) else {
            XCTFail()
            return
        }
        
        XCTAssert(declaredObject == declaredObject2)
    }

    enum InvalidUpdate {
        case fileGroup
        case sharingGroup
        case mimeType
        case objectType
        case none
    }
    
    // Test for invalid changes to static properties of a file or declared object.
    func runKnownFileInfo(update: InvalidUpdate) throws {
        let sharingGroupUUID = UUID()
        let fileUUID = UUID()
        let fileGroupUUID = UUID()
        
        let fileInfo = createFileInfo(fileUUID: fileUUID, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, mimeType: .text, deleted: false, fileVersion: 0, cloudStorageType: .Dropbox, objectType: "Foo")
        
        try syncServer.upsert(fileIndex: [fileInfo], sharingGroupUUID: sharingGroupUUID)
        
        switch update {
        case .fileGroup:
            fileInfo.fileGroupUUID = UUID().uuidString
        case .sharingGroup:
            fileInfo.sharingGroupUUID = UUID().uuidString
        case .mimeType:
            fileInfo.mimeType = MimeType.jpeg.rawValue
        case .objectType:
            fileInfo.objectType = "blarlby"
        case .none:
            break
        }
        
        // This simulates a second server `index` call for the same sharing group. But, this time the fileInfo record may have invalid changes.
        
        do {
            try syncServer.upsert(fileIndex: [fileInfo], sharingGroupUUID: sharingGroupUUID)
        } catch let error {
            if update == .none {
                XCTFail("\(error)")
                return
            }
            return
        }
        
        if update != .none {
            XCTFail()
            return
        }
    }
    
    func testKnownFileInfoWithFileGroupUpdateFails() throws {
        try runKnownFileInfo(update: .fileGroup)
    }
    
    func testKnownFileInfoWithSharingGroupUpdateFails() throws {
        try runKnownFileInfo(update: .sharingGroup)
    }
    
    func testKnownFileInfoWithMimeTypeUpdateFails() throws {
        try runKnownFileInfo(update: .mimeType)
    }
    
    func testKnownFileInfoWithNoInvalidUpdateWorks() throws {
        try runKnownFileInfo(update: .none)
    }
    
    func testSameFileUUIDTwiceFails() throws {
        let sharingGroupUUID = UUID()
        let fileUUID1 = UUID()
        let fileGroupUUID = UUID()
        
        let fileInfo1 = createFileInfo(fileUUID: fileUUID1, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, mimeType: .text, deleted: false, fileVersion: 0, cloudStorageType: .Dropbox, objectType: "Foo")
        
        do {
            try syncServer.upsert(fileIndex: [fileInfo1, fileInfo1], sharingGroupUUID: sharingGroupUUID)
        } catch {
            return
        }
        
        XCTFail()
    }
    
    // This reflects the case where another client initially uploads some of the files in a declared object, but other files in that declared object later.
    func testAdditionalDeclaredFilesInExistingDeclaredObjectAllowed() throws {
        let sharingGroupUUID = UUID()
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()
        let fileGroupUUID = UUID()
        
        let fileInfo1 = createFileInfo(fileUUID: fileUUID1, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, mimeType: .text, deleted: false, fileVersion: 0, cloudStorageType: .Dropbox, objectType: "Foo")
        
        // Add first fileUUID
        try syncServer.upsert(fileIndex: [fileInfo1], sharingGroupUUID: sharingGroupUUID)
        
        XCTAssert(try DirectoryEntry.numberRows(db: database) == 1)
        XCTAssert(try DeclaredObjectModel.numberRows(db: database) == 1)
        XCTAssert(try DeclaredFileModel.numberRows(db: database) == 1)
        
        // An additional file for the same file group
        
        let fileInfo2 = createFileInfo(fileUUID: fileUUID2, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, mimeType: .text, deleted: false, fileVersion: 0, cloudStorageType: .Dropbox, objectType: "Foo")
        
        // Another fileUUID for the same initially declared object

        try syncServer.upsert(fileIndex: [fileInfo1, fileInfo2], sharingGroupUUID: sharingGroupUUID)
        
        XCTAssert(try DirectoryEntry.numberRows(db: database) == 2)
        XCTAssert(try DeclaredObjectModel.numberRows(db: database) == 1)
        XCTAssert(try DeclaredFileModel.numberRows(db: database) == 2)
    }
    
    // Multiple file groups within the sharing group
    
    func testMultipleFileGroupsWorks() throws {
        let sharingGroupUUID = UUID()
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()
        let fileGroupUUID1 = UUID()
        let fileGroupUUID2 = UUID()

        let fileInfo1 = createFileInfo(fileUUID: fileUUID1, fileGroupUUID: fileGroupUUID1, sharingGroupUUID: sharingGroupUUID, mimeType: .text, deleted: false, fileVersion: 0, cloudStorageType: .Dropbox, objectType: "Foo")
        let fileInfo2 = createFileInfo(fileUUID: fileUUID2, fileGroupUUID: fileGroupUUID2, sharingGroupUUID: sharingGroupUUID, mimeType: .text, deleted: false, fileVersion: 0, cloudStorageType: .Dropbox, objectType: "Foo")
        
        try syncServer.upsert(fileIndex: [fileInfo1, fileInfo2], sharingGroupUUID: sharingGroupUUID)
        
        XCTAssert(try DirectoryEntry.numberRows(db: database) == 2)
        XCTAssert(try DeclaredObjectModel.numberRows(db: database) == 2)
        XCTAssert(try DeclaredFileModel.numberRows(db: database) == 2)
    }
}
