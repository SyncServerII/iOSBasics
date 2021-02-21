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
    var handlersObjectType: String?
    
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
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, reachability: FakeReachability(), configuration: config, signIns: fakeSignIns)
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        syncServer.helperDelegate = self

        handlers.objectType = { _, _ in
            return self.handlersObjectType
        }
        
        handlersObjectType = nil
    }

    override func tearDownWithError() throws {
    }

    func testEmptyFileIndexDoesNotFail() throws {
        try syncServer.upsert(fileIndex: [], sharingGroupUUID: UUID())
    }
    
    func createFileInfo(fileUUID: UUID, fileGroupUUID:UUID, sharingGroupUUID:UUID, mimeType: MimeType, deleted: Bool, fileVersion: FileVersionInt, cloudStorageType: CloudStorageType, objectType: String, fileLabel: String, creationDate: Date = Date()) -> FileInfo {
    
        let fileInfo = FileInfo()
        fileInfo.fileUUID = fileUUID.uuidString
        fileInfo.fileGroupUUID = fileGroupUUID.uuidString
        fileInfo.sharingGroupUUID = sharingGroupUUID.uuidString
        fileInfo.mimeType = mimeType.rawValue
        fileInfo.deleted = deleted
        fileInfo.fileVersion = fileVersion
        fileInfo.cloudStorageType = cloudStorageType.rawValue
        fileInfo.objectType = objectType
        fileInfo.fileLabel = fileLabel
        fileInfo.creationDate = creationDate
        
        return fileInfo
    }
    
    func runWithFileIndex(matchingSharingGroup: Bool) throws {
        let sharingGroupUUID = UUID()
        
        let fileInfoSharingGroupUUID: UUID
        if matchingSharingGroup {
            fileInfoSharingGroupUUID = sharingGroupUUID
        }
        else {
            fileInfoSharingGroupUUID = UUID()
        }
        
        let objectType = "Foo"
        let fileGroupUUID = UUID()
        let cloudStorageType: CloudStorageType = .Dropbox
        
        let fileDeclaration = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let declaredObject = try DeclaredObjectModel(db: database, objectType: objectType, files: [fileDeclaration])
        try declaredObject.insert()
        
        let objectEntry = try DirectoryObjectEntry(db: database, objectType: objectType, fileGroupUUID: fileGroupUUID, sharingGroupUUID: fileInfoSharingGroupUUID, cloudStorageType: cloudStorageType, deletedLocally: false, deletedOnServer: false)
        try objectEntry.insert()
        
        let fileInfo = createFileInfo(fileUUID: UUID(), fileGroupUUID: UUID(), sharingGroupUUID: fileInfoSharingGroupUUID, mimeType: .text, deleted: true, fileVersion: 0, cloudStorageType: cloudStorageType, objectType: "Foo", fileLabel: fileDeclaration.fileLabel)
        
        do {
            try syncServer.upsert(fileIndex: [fileInfo], sharingGroupUUID: sharingGroupUUID)
        } catch let error {
            if matchingSharingGroup {
                XCTFail("\(error)")
            }
            return
        }
        
        if !matchingSharingGroup {
            XCTFail()
        }
    }
    
    func testFileIndexWithMismatchingSharingGroupFails() throws {
        try runWithFileIndex(matchingSharingGroup: false)
    }
    
    func testFileIndexWithMatchingSharingGroupWorks() throws {
        try runWithFileIndex(matchingSharingGroup: true)
    }
    
    func testNewFileInfoAddsExpectedDatabaseRecords() throws {
        let sharingGroupUUID = UUID()

        let fileUUID = UUID()
        let fileGroupUUID = UUID()
        let objectType = "Foo"
        
        let fileDeclaration = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let declaredObject = try DeclaredObjectModel(db: database, objectType: objectType, files: [fileDeclaration])
        try declaredObject.insert()
        
        let fileInfo = createFileInfo(fileUUID: fileUUID, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, mimeType: .text, deleted: true, fileVersion: 0, cloudStorageType: .Dropbox, objectType: objectType, fileLabel: fileDeclaration.fileLabel)
        
        try syncServer.upsert(fileIndex: [fileInfo], sharingGroupUUID: sharingGroupUUID)
        
        // Expect: DirectoryFileEntry, DirectoryObjectEntry

        guard let fileEntry = try DirectoryFileEntry.fetchSingleRow(db: database, where: DirectoryFileEntry.fileUUIDField.description == fileUUID) else {
            XCTFail()
            return
        }
        
        XCTAssert(fileEntry.fileUUID.uuidString == fileInfo.fileUUID)
        XCTAssert(fileEntry.fileGroupUUID == fileGroupUUID)
        XCTAssert(fileEntry.deletedLocally == fileInfo.deleted)
        XCTAssert(fileEntry.deletedOnServer == fileInfo.deleted)
        XCTAssert(fileEntry.serverFileVersion == fileInfo.fileVersion)
        XCTAssert(fileEntry.fileVersion == nil)
        
        guard let objectEntry = try DirectoryObjectEntry.fetchSingleRow(db: database, where: DirectoryObjectEntry.fileGroupUUIDField.description == fileGroupUUID) else {
            XCTFail()
            return
        }

        XCTAssert(objectEntry.fileGroupUUID == fileGroupUUID)
        XCTAssert(objectEntry.sharingGroupUUID == sharingGroupUUID)
        XCTAssert(objectEntry.objectType == objectType)
        XCTAssert(objectEntry.cloudStorageType.rawValue == fileInfo.cloudStorageType)
        XCTAssert(objectEntry.deletedLocally == fileInfo.deleted)
        XCTAssert(objectEntry.deletedOnServer == fileInfo.deleted)
    }
    
    func testKnownFileInfoDoesNotAddOrChangeDatabaseRecords() throws {
        let sharingGroupUUID = UUID()
        let fileUUID = UUID()
        let fileGroupUUID = UUID()
        let objectType = "Foo"
        
        let fileDeclaration = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let declaredObject = try DeclaredObjectModel(db: database, objectType: objectType, files: [fileDeclaration])
        try declaredObject.insert()
        
        let fileInfo = createFileInfo(fileUUID: fileUUID, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, mimeType: .text, deleted: true, fileVersion: 0, cloudStorageType: .Dropbox, objectType: objectType, fileLabel: fileDeclaration.fileLabel)
        
        try syncServer.upsert(fileIndex: [fileInfo], sharingGroupUUID: sharingGroupUUID)

        guard let fileEntry = try DirectoryFileEntry.fetchSingleRow(db: database, where: DirectoryFileEntry.fileUUIDField.description == fileUUID) else {
            XCTFail()
            return
        }
        
        guard let objectEntry = try DirectoryObjectEntry.fetchSingleRow(db: database, where: DirectoryObjectEntry.fileGroupUUIDField.description == fileGroupUUID) else {
            XCTFail()
            return
        }
        
        XCTAssert(try DirectoryFileEntry.numberRows(db: database) == 1)
        XCTAssert(try DeclaredObjectModel.numberRows(db: database) == 1)
        XCTAssert(try DirectoryObjectEntry.numberRows(db: database) == 1)
        
        // This simulates a second server `index` call for the same sharing group. It should not alter the database.
        try syncServer.upsert(fileIndex: [fileInfo], sharingGroupUUID: sharingGroupUUID)

        XCTAssert(try DirectoryFileEntry.numberRows(db: database) == 1)
        XCTAssert(try DeclaredObjectModel.numberRows(db: database) == 1)
        XCTAssert(try DirectoryObjectEntry.numberRows(db: database) == 1)

        guard let fileEntry2 = try DirectoryFileEntry.fetchSingleRow(db: database, where: DirectoryFileEntry.fileUUIDField.description == fileUUID) else {
            XCTFail()
            return
        }
        
        guard let objectEntry2 = try DirectoryObjectEntry.fetchSingleRow(db: database, where: DirectoryObjectEntry.fileGroupUUIDField.description == fileGroupUUID) else {
            XCTFail()
            return
        }
        
        guard let declaredObject2 = try DeclaredObjectModel.fetchSingleRow(db: database, where: DeclaredObjectModel.objectTypeField.description == objectType) else {
            XCTFail()
            return
        }
        
        XCTAssert(fileEntry == fileEntry2)
        XCTAssert(objectEntry == objectEntry2)
        XCTAssert(declaredObject == declaredObject2)
    }
    
    func testKnownFileInfoWithValidUpdateChangesDatabaseRecord() throws {
        let sharingGroupUUID = UUID()
        let fileUUID = UUID()
        let fileGroupUUID = UUID()
        let objectType = "Foo"
        
        let fileDeclaration = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let declaredObject = try DeclaredObjectModel(db: database, objectType: objectType, files: [fileDeclaration])
        try declaredObject.insert()
        
        let fileInfo = createFileInfo(fileUUID: fileUUID, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, mimeType: .text, deleted: false, fileVersion: 0, cloudStorageType: .Dropbox, objectType: objectType, fileLabel: fileDeclaration.fileLabel)
        
        try syncServer.upsert(fileIndex: [fileInfo], sharingGroupUUID: sharingGroupUUID)
        
        guard let objectEntry = try DirectoryObjectEntry.fetchSingleRow(db: database, where: DirectoryObjectEntry.fileGroupUUIDField.description == fileGroupUUID) else {
            XCTFail()
            return
        }
        
        guard let declaredObject2 = try DeclaredObjectModel.fetchSingleRow(db: database, where: DeclaredObjectModel.objectTypeField.description == objectType) else {
            XCTFail()
            return
        }
        
        XCTAssert(try DirectoryFileEntry.numberRows(db: database) == 1)
        XCTAssert(try DeclaredObjectModel.numberRows(db: database) == 1)
        XCTAssert(try DirectoryObjectEntry.numberRows(db: database) == 1)
        
        // This simulates a second server `index` call for the same sharing group. But, this time the fileInfo record has valid changes.
        fileInfo.deleted = true
        fileInfo.fileVersion = 1
        
        try syncServer.upsert(fileIndex: [fileInfo], sharingGroupUUID: sharingGroupUUID)

        XCTAssert(try DirectoryFileEntry.numberRows(db: database) == 1)
        XCTAssert(try DeclaredObjectModel.numberRows(db: database) == 1)
        XCTAssert(try DirectoryObjectEntry.numberRows(db: database) == 1)
        
        guard let fileEntry2 = try DirectoryFileEntry.fetchSingleRow(db: database, where: DirectoryFileEntry.fileUUIDField.description == fileUUID) else {
            XCTFail()
            return
        }
        
        guard let objectEntry2 = try DirectoryObjectEntry.fetchSingleRow(db: database, where: DirectoryObjectEntry.fileGroupUUIDField.description == fileGroupUUID) else {
            XCTFail()
            return
        }
        
        guard let declaredObject3 = try DeclaredObjectModel.fetchSingleRow(db: database, where: DeclaredObjectModel.objectTypeField.description == objectType) else {
            XCTFail()
            return
        }
        
        XCTAssert(fileEntry2.serverFileVersion == fileInfo.fileVersion)
        XCTAssert(fileEntry2.fileVersion == nil)
        XCTAssert(fileEntry2.deletedOnServer)
        XCTAssert(!fileEntry2.deletedLocally)
        
        XCTAssert(declaredObject == declaredObject2)
        XCTAssert(declaredObject2 == declaredObject3)
        
        XCTAssert(objectEntry == objectEntry2)
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
        let objectType = "Foo"
        
        let fileDeclaration = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let declaredObject = try DeclaredObjectModel(db: database, objectType: objectType, files: [fileDeclaration])
        try declaredObject.insert()
        
        let fileInfo = createFileInfo(fileUUID: fileUUID, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, mimeType: .text, deleted: false, fileVersion: 0, cloudStorageType: .Dropbox, objectType: objectType, fileLabel: fileDeclaration.fileLabel)
        
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
        let objectType = "objectType"
        
        let fileDeclaration = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let declaredObject = try DeclaredObjectModel(db: database, objectType: objectType, files: [fileDeclaration])
        try declaredObject.insert()
        
        let fileInfo1 = createFileInfo(fileUUID: fileUUID1, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, mimeType: .text, deleted: false, fileVersion: 0, cloudStorageType: .Dropbox, objectType: "Foo", fileLabel: fileDeclaration.fileLabel)
        
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
        let objectType = "objectType"
        
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let declaredObject1 = try DeclaredObjectModel(db: database, objectType: objectType, files: [fileDeclaration1])
        try declaredObject1.insert()
        
        let fileInfo1 = createFileInfo(fileUUID: fileUUID1, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, mimeType: .text, deleted: false, fileVersion: 0, cloudStorageType: .Dropbox, objectType: objectType, fileLabel: fileDeclaration1.fileLabel)
        
        // Add first fileUUID
        try syncServer.upsert(fileIndex: [fileInfo1], sharingGroupUUID: sharingGroupUUID)
        
        XCTAssert(try DirectoryFileEntry.numberRows(db: database) == 1)
        XCTAssert(try DeclaredObjectModel.numberRows(db: database) == 1)
        XCTAssert(try DirectoryObjectEntry.numberRows(db: database) == 1)
        
        // An additional file for the same file group
        
        let fileInfo2 = createFileInfo(fileUUID: fileUUID2, fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID, mimeType: .text, deleted: false, fileVersion: 0, cloudStorageType: .Dropbox, objectType: objectType, fileLabel: fileDeclaration1.fileLabel)
        
        // Another fileUUID for the same initially declared object

        try syncServer.upsert(fileIndex: [fileInfo1, fileInfo2], sharingGroupUUID: sharingGroupUUID)
        
        XCTAssert(try DirectoryFileEntry.numberRows(db: database) == 2)
        XCTAssert(try DeclaredObjectModel.numberRows(db: database) == 1)
        XCTAssert(try DirectoryObjectEntry.numberRows(db: database) == 1)
    }
    
    // Multiple file groups within the sharing group
    
    func testMultipleFileGroupsWorks() throws {
        let sharingGroupUUID = UUID()
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()
        let fileGroupUUID1 = UUID()
        let fileGroupUUID2 = UUID()
        
        let objectType = "objectType"
        
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let declaredObject1 = try DeclaredObjectModel(db: database, objectType: objectType, files: [fileDeclaration1])
        try declaredObject1.insert()

        let fileInfo1 = createFileInfo(fileUUID: fileUUID1, fileGroupUUID: fileGroupUUID1, sharingGroupUUID: sharingGroupUUID, mimeType: .text, deleted: false, fileVersion: 0, cloudStorageType: .Dropbox, objectType: objectType, fileLabel: fileDeclaration1.fileLabel)
        let fileInfo2 = createFileInfo(fileUUID: fileUUID2, fileGroupUUID: fileGroupUUID2, sharingGroupUUID: sharingGroupUUID, mimeType: .text, deleted: false, fileVersion: 0, cloudStorageType: .Dropbox, objectType: objectType, fileLabel: fileDeclaration1.fileLabel)
        
        try syncServer.upsert(fileIndex: [fileInfo1, fileInfo2], sharingGroupUUID: sharingGroupUUID)
        
        XCTAssert(try DirectoryFileEntry.numberRows(db: database) == 2)
        XCTAssert(try DeclaredObjectModel.numberRows(db: database) == 1)
        XCTAssert(try DirectoryObjectEntry.numberRows(db: database) == 2)
    }
    
    func testMissingObjectType() throws {
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let sharingGroupUUID = UUID()
        let fileGroupUUID = UUID()
        let fileUUID = UUID()
        
        let fileInfo = FileInfo()
        fileInfo.fileUUID = fileUUID.uuidString
        fileInfo.fileGroupUUID = fileGroupUUID.uuidString
        fileInfo.sharingGroupUUID = sharingGroupUUID.uuidString
        fileInfo.mimeType = MimeType.text.rawValue
        fileInfo.deleted = false
        fileInfo.fileVersion = 0
        fileInfo.cloudStorageType = CloudStorageType.Dropbox.rawValue
        fileInfo.objectType = nil
        fileInfo.fileLabel = "file1"
        fileInfo.creationDate = Date()
        
        // Must have some app meta data in order for the handler object type to be used.
        fileInfo.appMetaData = "Something"
        
        handlersObjectType = objectType
        
        try syncServer.upsert(fileIndex: [fileInfo], sharingGroupUUID: sharingGroupUUID)
        
        guard let objectEntry = try DirectoryObjectEntry.fetchSingleRow(db: database, where: DirectoryObjectEntry.fileGroupUUIDField.description == fileGroupUUID) else {
            XCTFail()
            return
        }
        
        guard let fileEntry = try DirectoryFileEntry.fetchSingleRow(db: database, where: DirectoryFileEntry.fileUUIDField.description == fileUUID) else {
            XCTFail()
            return
        }
        
        XCTAssert(fileEntry.fileLabel == fileInfo.fileLabel)
        XCTAssert(objectEntry.objectType == objectType)
    }
    
    func testMissingFileLabel() throws {
        let objectType = "Foo"
        let fileLabel = "file1"
        
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1], appMetaDataMapping: ["a": fileLabel])
        try syncServer.register(object: example)
        
        let sharingGroupUUID = UUID()
        let fileGroupUUID = UUID()
        let fileUUID = UUID()
        
        let fileInfo = FileInfo()
        fileInfo.fileUUID = fileUUID.uuidString
        fileInfo.fileGroupUUID = fileGroupUUID.uuidString
        fileInfo.sharingGroupUUID = sharingGroupUUID.uuidString
        fileInfo.mimeType = MimeType.text.rawValue
        fileInfo.deleted = false
        fileInfo.fileVersion = 0
        fileInfo.cloudStorageType = CloudStorageType.Dropbox.rawValue
        fileInfo.objectType = objectType
        fileInfo.fileLabel = nil
        fileInfo.creationDate = Date()
        
        // Must have some app meta data in order for the handler object type to be used.
        fileInfo.appMetaData = "a"
                
        try syncServer.upsert(fileIndex: [fileInfo], sharingGroupUUID: sharingGroupUUID)
        
        guard let objectEntry = try DirectoryObjectEntry.fetchSingleRow(db: database, where: DirectoryObjectEntry.fileGroupUUIDField.description == fileGroupUUID) else {
            XCTFail()
            return
        }
        
        guard let fileEntry = try DirectoryFileEntry.fetchSingleRow(db: database, where: DirectoryFileEntry.fileUUIDField.description == fileUUID) else {
            XCTFail()
            return
        }
        
        XCTAssert(fileEntry.fileLabel == fileLabel)
        XCTAssert(objectEntry.objectType == objectType)
    }
    
    func testMissingObjectTypeAndFileLabel() throws {
        let objectType = "Foo"
        let fileLabel = "file1"
        
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1], appMetaDataMapping: ["a": fileLabel])
        try syncServer.register(object: example)
        
        let sharingGroupUUID = UUID()
        let fileGroupUUID = UUID()
        let fileUUID = UUID()
        
        let fileInfo = FileInfo()
        fileInfo.fileUUID = fileUUID.uuidString
        fileInfo.fileGroupUUID = fileGroupUUID.uuidString
        fileInfo.sharingGroupUUID = sharingGroupUUID.uuidString
        fileInfo.mimeType = MimeType.text.rawValue
        fileInfo.deleted = false
        fileInfo.fileVersion = 0
        fileInfo.cloudStorageType = CloudStorageType.Dropbox.rawValue
        fileInfo.objectType = nil
        fileInfo.fileLabel = nil
        fileInfo.creationDate = Date()
        
        // Must have some app meta data in order for the handler object type to be used.
        fileInfo.appMetaData = "a"
        
        handlersObjectType = objectType
        
        try syncServer.upsert(fileIndex: [fileInfo], sharingGroupUUID: sharingGroupUUID)
        
        guard let objectEntry = try DirectoryObjectEntry.fetchSingleRow(db: database, where: DirectoryObjectEntry.fileGroupUUIDField.description == fileGroupUUID) else {
            XCTFail()
            return
        }
        
        guard let fileEntry = try DirectoryFileEntry.fetchSingleRow(db: database, where: DirectoryFileEntry.fileUUIDField.description == fileUUID) else {
            XCTFail()
            return
        }
        
        XCTAssert(fileEntry.fileLabel == fileLabel)
        XCTAssert(objectEntry.objectType == objectType)
    }
}
