import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn
@testable import TestsCommon

class UploadQueueTests_V0_SingleObjectDeclaration: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, Delegate, SyncServerTests {
    var deviceUUID: UUID!
    var hashingManager: HashingManager!
    var api: ServerAPI!
    var syncServer: SyncServer!
    var handlers = DelegateHandlers()
    var database: Connection!
    var config:Configuration!
    var fakeHelper:SignInServicesHelperFake!

    override func setUpWithError() throws {
        try super.setUpWithError()
        set(logLevel: .trace)
        handlers = DelegateHandlers()
        handlers.user = try dropboxUser()
        deviceUUID = UUID()
        database = try Connection(.inMemory)
        hashingManager = HashingManager()
        try hashingManager.add(hashing: handlers.user.hashing)
        let serverURL = URL(string: Self.baseURL())!
        config = Configuration(appGroupIdentifier: nil, serverURL: serverURL, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true)
        fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, configuration: config, signIns: fakeSignIns)
        api = syncServer.api
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        
        _ = handlers.user.removeUser()
        guard handlers.user.addUser() else {
            throw SyncServerError.internalError("Could not add user")
        }
        
        // So as to not throw an error in `contentsOfDirectory`
        try Files.createDirectoryIfNeeded(config.temporaryFiles.directory)
        
        let filePaths = try FileManager.default.contentsOfDirectory(atPath: config.temporaryFiles.directory.path)
        for filePath in filePaths {
            let url = config.temporaryFiles.directory.appendingPathComponent(filePath)
            try FileManager.default.removeItem(at: url)
        }
        
        syncServer.helperDelegate = self
        handlers.objectType = { _, _ in
            return nil
        }
    }

    override func tearDownWithError() throws {
        // All temporary files should have been removed prior to end of test.
        let filePaths = try FileManager.default.contentsOfDirectory(atPath: config.temporaryFiles.directory.path)        
        XCTAssert(filePaths.count == 0, "\(filePaths.count)")
    }
    
    func runUpload(withNoFiles: Bool) throws {
        let sharingGroupUUID = try getSharingGroup(db: database)

        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.jpeg], changeResolverName: nil)
         
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .copy(exampleTextFileURL), uuid: UUID())
        
        var uploads = [FileUpload]()
        if !withNoFiles {
            uploads += [file1]
        }
        
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: uploads)

        let directoryObjectEntryCount = try DirectoryObjectEntry.numberRows(db: database)
        let directoryFileEntryCount = try DirectoryFileEntry.numberRows(db: database)
        let objectTrackerCount = try UploadObjectTracker.numberRows(db: database)
        let fileTrackerCount = try UploadFileTracker.numberRows(db: database)
        
        do {
            try syncServer.queue(upload: upload)
        } catch (let error) {
            if !withNoFiles {
                XCTFail("\(error)")
            }
            return
        }
        
        if withNoFiles {
            XCTFail()
            return
        }
        
        waitForUploadsToComplete(numberUploads: 1)
        
        // Check for new directory entries.
        XCTAssert(try DirectoryObjectEntry.numberRows(db: database) == directoryObjectEntryCount + 1)
        XCTAssert(try DirectoryFileEntry.numberRows(db: database) == directoryFileEntryCount + 1)
        
        // There should be no change in the tracker counts-- they should have been removed after the uploads.
        XCTAssert(try UploadObjectTracker.numberRows(db: database) == objectTrackerCount)
        XCTAssert(try UploadFileTracker.numberRows(db: database) == fileTrackerCount)
    }
    
    func testUploadWithNoFilesFails() throws {
        try runUpload(withNoFiles: true)
    }
    
    func testUploadWithFilesWorks() throws {
        try runUpload(withNoFiles: false)
    }
    
    func runUpload(duplicatedUUID: Bool) throws {
        let sharingGroupUUID = try getSharingGroup(db: database)
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.jpeg], changeResolverName: nil)
        let fileDeclaration2 = FileDeclaration(fileLabel: "file2", mimeTypes: [.jpeg], changeResolverName: nil)

        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1, fileDeclaration2])
        try syncServer.register(object: example)
        
        let fileUUID1 = UUID()
        let fileUUID2:UUID
        
        if duplicatedUUID {
            fileUUID2 = fileUUID1
        }
        else {
            fileUUID2 = UUID()
        }
        
        let fileUpload1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .copy(exampleTextFileURL), uuid: fileUUID1)
        let fileUpload2 = FileUpload(fileLabel: fileDeclaration2.fileLabel, dataSource: .copy(exampleTextFileURL), uuid: fileUUID2)

        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload1, fileUpload2])

        let directoryObjectEntryCount = try DirectoryObjectEntry.numberRows(db: database)
        let directoryFileEntryCount = try DirectoryFileEntry.numberRows(db: database)
        let objectTrackerCount = try UploadObjectTracker.numberRows(db: database)
        let fileTrackerCount = try UploadFileTracker.numberRows(db: database)
        
        do {
            try syncServer.queue(upload: upload)
        } catch let error {
            if !duplicatedUUID {
                XCTFail("\(error)")
            }
            return
        }
        
        if duplicatedUUID {
            XCTFail()
            return
        }
        
        waitForUploadsToComplete(numberUploads: 2)
        
        // Check for new directory entries.
        XCTAssert(try DirectoryObjectEntry.numberRows(db: database) == directoryObjectEntryCount + 1)
        XCTAssert(try DirectoryFileEntry.numberRows(db: database) == directoryFileEntryCount + 2)
        
        // There should be no change in the tracker counts-- they should have been removed after the uploads.
        XCTAssert(try UploadObjectTracker.numberRows(db: database) == objectTrackerCount)
        XCTAssert(try UploadFileTracker.numberRows(db: database) == fileTrackerCount)
    }
    
    func testUploadWithDuplicatedUUIDsFails() throws {
        try runUpload(duplicatedUUID: true)
    }
    
    func testUploadWithoutDuplicatedUUIDsWorks() throws {
        try runUpload(duplicatedUUID: false)
    }
    
    func runQueueObject(knownObjectType:Bool) throws {
        let sharingGroupUUID = try getSharingGroup(db: database)
        
        let objectType = "Foo"
        let fileDeclaration = FileDeclaration(fileLabel: "file1", mimeTypes: [.jpeg], changeResolverName: nil)
            
        if knownObjectType {
            let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration])
            try syncServer.register(object: example)
        }
        
        let file = FileUpload(fileLabel: fileDeclaration.fileLabel, dataSource: .copy(exampleTextFileURL), uuid: UUID())
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: [file])

        let directoryObjectEntryCount = try DirectoryObjectEntry.numberRows(db: database)
        let directoryFileEntryCount = try DirectoryFileEntry.numberRows(db: database)
        let objectTrackerCount = try UploadObjectTracker.numberRows(db: database)
        let fileTrackerCount = try UploadFileTracker.numberRows(db: database)
        
        do {
            try syncServer.queue(upload: upload)
        } catch {
            if knownObjectType {
                XCTFail()
            }
            return
        }
        
        if !knownObjectType {
            XCTFail()
            return
        }
        
        waitForUploadsToComplete(numberUploads: 1)
        
        // Check for new directory entries.
        XCTAssert(try DirectoryObjectEntry.numberRows(db: database) == directoryObjectEntryCount + 1)
        XCTAssert(try DirectoryFileEntry.numberRows(db: database) == directoryFileEntryCount + 1)
        
        // There should be no change in the tracker counts-- they should have been removed after the uploads.
        XCTAssert(try UploadObjectTracker.numberRows(db: database) == objectTrackerCount)
        XCTAssert(try UploadFileTracker.numberRows(db: database) == fileTrackerCount)
    }
    
    func testUploadObjectWithUnknownObjectTypeFails() throws {
        try runQueueObject(knownObjectType:false)
    }
    
    func testUploadObjectWithKnownObjectTypeWorks() throws {
        try runQueueObject(knownObjectType:true)
    }
    
    func uploadObject(duplicateFileLabel: Bool) throws {
        let sharingGroupUUID = try getSharingGroup(db: database)

        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.jpeg], changeResolverName: nil)
        let fileDeclaration2 = FileDeclaration(fileLabel: "file2", mimeTypes: [.jpeg], changeResolverName: nil)
         
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1, fileDeclaration2])
        try syncServer.register(object: example)
        
        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .copy(exampleTextFileURL), uuid: UUID())
        let file2 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .copy(exampleTextFileURL), uuid: UUID())
        
        var uploads = [file1]
        if duplicateFileLabel {
            uploads += [file2]
        }
        
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: uploads)

        let directoryObjectEntryCount = try DirectoryObjectEntry.numberRows(db: database)
        let directoryFileEntryCount = try DirectoryFileEntry.numberRows(db: database)
        let objectTrackerCount = try UploadObjectTracker.numberRows(db: database)
        let fileTrackerCount = try UploadFileTracker.numberRows(db: database)
        
        do {
            try syncServer.queue(upload: upload)
        } catch {
            if !duplicateFileLabel {
                XCTFail()
            }
            return
        }
        
        if duplicateFileLabel {
            XCTFail()
            return
        }

        waitForUploadsToComplete(numberUploads: 1)
        
        // Check for new directory entries.
        XCTAssert(try DirectoryObjectEntry.numberRows(db: database) == directoryObjectEntryCount + 1)
        XCTAssert(try DirectoryFileEntry.numberRows(db: database) == directoryFileEntryCount + 1)
        
        // There should be no change in the tracker counts-- they should have been removed after the uploads.
        XCTAssert(try UploadObjectTracker.numberRows(db: database) == objectTrackerCount)
        XCTAssert(try UploadFileTracker.numberRows(db: database) == fileTrackerCount)
    }
    
    func testUploadObjectWithDuplicateFileLabelFails() throws {
        try uploadObject(duplicateFileLabel: true)
    }
    
    func testUploadObjectWithNonDuplicateFileLabelWorks() throws {
        try uploadObject(duplicateFileLabel: false)
    }
    
    func runUpload(withUnknownLabel: Bool) throws {
        let sharingGroupUUID = try getSharingGroup(db: database)

        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.jpeg], changeResolverName: nil)

        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let fileLabel: String
        if withUnknownLabel {
            fileLabel = "file2"
        }
        else {
            fileLabel = fileDeclaration1.fileLabel
        }
        
        let fileUpload1 = FileUpload(fileLabel: fileLabel, dataSource: .copy(exampleTextFileURL), uuid: UUID())

        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload1])

        let directoryObjectEntryCount = try DirectoryObjectEntry.numberRows(db: database)
        let directoryFileEntryCount = try DirectoryFileEntry.numberRows(db: database)
        let objectTrackerCount = try UploadObjectTracker.numberRows(db: database)
        let fileTrackerCount = try UploadFileTracker.numberRows(db: database)
        
        do {
            try syncServer.queue(upload: upload)
        } catch let error {
            if !withUnknownLabel {
                XCTFail("\(error)")
            }
            return
        }
        
        if withUnknownLabel {
            XCTFail()
            return
        }
        
        waitForUploadsToComplete(numberUploads: 1)
        
        // Check for new directory entries.
        XCTAssert(try DirectoryObjectEntry.numberRows(db: database) == directoryObjectEntryCount + 1)
        XCTAssert(try DirectoryFileEntry.numberRows(db: database) == directoryFileEntryCount + 1)
        
        // There should be no change in the tracker counts-- they should have been removed after the uploads.
        XCTAssert(try UploadObjectTracker.numberRows(db: database) == objectTrackerCount)
        XCTAssert(try UploadFileTracker.numberRows(db: database) == fileTrackerCount)
    }
    
    func testWithV0UploadWithUnknownLabelFails() throws {
        try runUpload(withUnknownLabel: true)
    }
    
    func testV0UploadWithKnownLabelWorks() throws {
        try runUpload(withUnknownLabel: false)
    }
    
    func runUpload(withKnownSharingGroup: Bool) throws {
        var sharingGroupUUID = try getSharingGroup(db: database)
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.jpeg], changeResolverName: nil)

        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let fileUpload1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .copy(exampleTextFileURL), uuid: UUID())

        if !withKnownSharingGroup {
            sharingGroupUUID = UUID()
        }

        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload1])
        
        let directoryObjectEntryCount = try DirectoryObjectEntry.numberRows(db: database)
        let directoryFileEntryCount = try DirectoryFileEntry.numberRows(db: database)
        let objectTrackerCount = try UploadObjectTracker.numberRows(db: database)
        let fileTrackerCount = try UploadFileTracker.numberRows(db: database)

        do {
            try syncServer.queue(upload: upload)
        } catch let error {
            if withKnownSharingGroup {
                XCTFail("\(error)")
            }
            return
        }
        
        if !withKnownSharingGroup {
            XCTFail()
            return
        }
        
        waitForUploadsToComplete(numberUploads: 1)
        
        // Check for new directory entries.
        XCTAssert(try DirectoryObjectEntry.numberRows(db: database) == directoryObjectEntryCount + 1)
        XCTAssert(try DirectoryFileEntry.numberRows(db: database) == directoryFileEntryCount + 1)
        
        // There should be no change in the tracker counts-- they should have been removed after the uploads.
        XCTAssert(try UploadObjectTracker.numberRows(db: database) == objectTrackerCount)
        XCTAssert(try UploadFileTracker.numberRows(db: database) == fileTrackerCount)
    }
    
    func testUploadWithUnknownSharingGroupFails() throws {
        try runUpload(withKnownSharingGroup: false)
    }
    
    func testUploadWithKnownSharingGroupWorks() throws {
        try runUpload(withKnownSharingGroup: true)
    }
    
    func runUpload(withDeletedSharingGroup: Bool) throws {
        let sharingGroupUUID = try getSharingGroup(db: database)
        if withDeletedSharingGroup {
            let exp = expectation(description: "exp")
            syncServer.removeFromSharingGroup(sharingGroupUUID: sharingGroupUUID) { error in
                XCTAssertNil(error)
                exp.fulfill()
            }
            waitForExpectations(timeout: 10, handler: nil)
            
            try self.sync()
        }
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.jpeg], changeResolverName: nil)

        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let fileUpload1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .copy(exampleTextFileURL), uuid: UUID())
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload1])
        
        let directoryObjectEntryCount = try DirectoryObjectEntry.numberRows(db: database)
        let directoryFileEntryCount = try DirectoryFileEntry.numberRows(db: database)
        let objectTrackerCount = try UploadObjectTracker.numberRows(db: database)
        let fileTrackerCount = try UploadFileTracker.numberRows(db: database)

        do {
            try syncServer.queue(upload: upload)
        } catch let error {
            if !withDeletedSharingGroup {
                XCTFail("\(error)")
            }
            return
        }
        
        if withDeletedSharingGroup {
            XCTFail()
            return
        }
        
        waitForUploadsToComplete(numberUploads: 1)
        
        // Check for new directory entries.
        XCTAssert(try DirectoryObjectEntry.numberRows(db: database) == directoryObjectEntryCount + 1)
        XCTAssert(try DirectoryFileEntry.numberRows(db: database) == directoryFileEntryCount + 1)
        
        // There should be no change in the tracker counts-- they should have been removed after the uploads.
        XCTAssert(try UploadObjectTracker.numberRows(db: database) == objectTrackerCount)
        XCTAssert(try UploadFileTracker.numberRows(db: database) == fileTrackerCount)
    }
    
    func testUploadWithDeletedSharingGroupFails() throws {
        try runUpload(withDeletedSharingGroup: true)
    }
    
    func testUploadWithNonDeletedSharingGroupWorks() throws {
        try runUpload(withDeletedSharingGroup: false)
    }
    
    func testQueueSingleImageFile() throws {
        let fileUUID1 = UUID()
        
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.jpeg], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let fileUpload1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .copy(exampleImageFileURL), uuid: fileUUID1)
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload1])
        try syncServer.queue(upload: upload)
        
        waitForUploadsToComplete(numberUploads: 1)
    }
    
    func testUploadFileGroupFilesInASeriesWorks() throws {
        let sharingGroupUUID = try getSharingGroup(db: database)

        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let fileDeclaration2 = FileDeclaration(fileLabel: "file2", mimeTypes: [.text], changeResolverName: nil)

        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1, fileDeclaration2])
        try syncServer.register(object: example)
        
        let file1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .copy(exampleTextFileURL), uuid: UUID())
        let upload1 = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: [file1])

        let directoryObjectEntryCount = try DirectoryObjectEntry.numberRows(db: database)
        let directoryFileEntryCount = try DirectoryFileEntry.numberRows(db: database)
        let objectTrackerCount = try UploadObjectTracker.numberRows(db: database)
        let fileTrackerCount = try UploadFileTracker.numberRows(db: database)
        
        try syncServer.queue(upload: upload1)
        waitForUploadsToComplete(numberUploads: 1)
        
        let file2 = FileUpload(fileLabel: fileDeclaration2.fileLabel, dataSource: .copy(exampleTextFileURL), uuid: UUID())
        let upload2 = ObjectUpload(objectType: objectType, fileGroupUUID: upload1.fileGroupUUID, sharingGroupUUID: sharingGroupUUID, uploads: [file2])
        try syncServer.queue(upload: upload2)
        waitForUploadsToComplete(numberUploads: 1)
        
        // Check for new directory entries.
        XCTAssert(try DirectoryObjectEntry.numberRows(db: database) == directoryObjectEntryCount + 1)
        XCTAssert(try DirectoryFileEntry.numberRows(db: database) == directoryFileEntryCount + 2)
        
        // There should be no change in the tracker counts-- they should have been removed after the uploads.
        XCTAssert(try UploadObjectTracker.numberRows(db: database) == objectTrackerCount)
        XCTAssert(try UploadFileTracker.numberRows(db: database) == fileTrackerCount)
    }
    
    func testUploadDeletedFileFails() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let localFile = Self.exampleTextFileURL
        
        let (uploadObject, _) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)

        try delete(object: uploadObject.fileGroupUUID)
        
        // Technically, this is wrong. Because we're trying to upload v1 of a file that doesn't have a change resolver. But the failure will be detected before that.
        
        do {
            try syncServer.queue(upload: uploadObject)
        } catch let error {
            guard let error = error as? SyncServerError else {
                XCTFail()
                return
            }
            
            XCTAssert(error == SyncServerError.attemptToQueueADeletedFile)
            return
        }
        
        XCTFail()
    }
    
    func testUploadWrongMimeTypeWithSingleMimeTypeInDeclaration() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        let objectType = "o1"
        let localFile = Self.exampleTextFileURL
        
        let fileUUID1 = UUID()
        
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1], objectWasDownloaded: nil)
        try syncServer.register(object: example)
        
        let fileUpload1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .jpeg, dataSource: .copy(localFile), uuid: fileUUID1)
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload1])
        
        do {
            try syncServer.queue(upload: upload)
        } catch let error {
            guard let syncServerError = error as? SyncServerError else {
                XCTFail()
                return
            }
            XCTAssert(syncServerError == .mimeTypeNotInDeclaration)
            return
        }
        
        XCTFail()
    }
    
    func testUploadWrongMimeTypeWithMultipleMimeTypeInDeclaration() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        let objectType = "o1"
        let localFile = Self.exampleTextFileURL
        
        let fileUUID1 = UUID()
        
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text, .png], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1], objectWasDownloaded: nil)
        try syncServer.register(object: example)
        
        let fileUpload1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .jpeg, dataSource: .copy(localFile), uuid: fileUUID1)
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload1])
        
        do {
            try syncServer.queue(upload: upload)
        } catch let error {
            guard let syncServerError = error as? SyncServerError else {
                XCTFail()
                return
            }
            XCTAssert(syncServerError == .mimeTypeNotInDeclaration)
            return
        }
        
        XCTFail()
    }
    
    func testUploadNilMimeTypeWhenMoreThanOneMimeTypeFails() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        let objectType = "o1"
        let localFile = Self.exampleTextFileURL
        
        let fileUUID1 = UUID()
        
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text, .jpeg], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1], objectWasDownloaded: nil)
        try syncServer.register(object: example)
        
        let fileUpload1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .copy(localFile), uuid: fileUUID1)
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload1])
        
        do {
            try syncServer.queue(upload: upload)
        } catch let error {
            guard let syncServerError = error as? SyncServerError else {
                XCTFail()
                return
            }
            XCTAssert(syncServerError == .nilUploadMimeTypeButNotJustOneMimeTypeInDeclaration)
            return
        }
        
        XCTFail()
    }
}
