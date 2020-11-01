import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn
@testable import TestsCommon

class UploadQueueTests_SingleObjectDeclaration: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, Delegate, SyncServerTests {
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
    }

    override func tearDownWithError() throws {
        // All temporary files should have been removed prior to end of test.
        let filePaths = try FileManager.default.contentsOfDirectory(atPath: config.temporaryFiles.directory.path)        
        XCTAssert(filePaths.count == 0, "\(filePaths.count)")
    }
    
    func runUpload(withNoFiles: Bool) throws {
        let sharingGroupUUID = try getSharingGroup()

        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeType: .jpeg, changeResolverName: nil)
         
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
        let sharingGroupUUID = try getSharingGroup()
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeType: .jpeg, changeResolverName: nil)
        let fileDeclaration2 = FileDeclaration(fileLabel: "file2", mimeType: .jpeg, changeResolverName: nil)

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
        let sharingGroupUUID = try getSharingGroup()
        
        let objectType = "Foo"
        let fileDeclaration = FileDeclaration(fileLabel: "file1", mimeType: .jpeg, changeResolverName: nil)
            
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
        let sharingGroupUUID = try getSharingGroup()

        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeType: .jpeg, changeResolverName: nil)
        let fileDeclaration2 = FileDeclaration(fileLabel: "file2", mimeType: .jpeg, changeResolverName: nil)
         
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
        let sharingGroupUUID = try getSharingGroup()

        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeType: .jpeg, changeResolverName: nil)

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
    
    // Temporary until I get `sync` working again
    func getSharingGroup(createEntry: Bool = true) throws -> UUID {
        let sharingGroup = try getSharingGroupUUID()
        
        if createEntry {
            let entry = try SharingEntry(db: database, permission: Permission.admin, deleted: false, sharingGroupName: nil, sharingGroupUUID: sharingGroup, sharingGroupUsers: [], cloudStorageType: CloudStorageType.Dropbox)
            try entry.insert()
        }
        
        return sharingGroup
    }
    
    func runUpload(withKnownSharingGroup: Bool) throws {
        var sharingGroupUUID = try getSharingGroup()
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeType: .jpeg, changeResolverName: nil)

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

//    func testUploadv0AndVNfilesTogetherFails() {
//        assert(false)
//    }
    
    // Test where all queued upload files have been uploaded already: All have change resolvers.
    
    // Test that all queued upload files have been uploaded already: Some do not have change resolvers. This should fail.
    
    // Test that none of the queued upload files have been uploaded already.
    
    // Test that only some of the new upload files are in the existing set: Should fail
    
        
    /*
    func runQueueTest(withDeclaredFiles: Bool) throws {
        let fileUUID1 = UUID()
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, appMetaData: nil, changeResolverName: nil)

        var declarations = Set<FileDeclaration>()
        if withDeclaredFiles {
            declarations.insert(declaration1)
        }
        
        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable1])

        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        do {
            try syncServer.queue(uploads: uploadables, declaration: testObject)
        } catch let error {
            if withDeclaredFiles {
                XCTFail("\(error)")
            }
            return
        }
        
        if !withDeclaredFiles {
            XCTFail()
            return
        }
        
        waitForUploadsToComplete(numberUploads: 1)
        
        XCTAssert(try UploadFileTracker.numberRows(db: database) == 0)
        XCTAssert(try UploadObjectTracker.numberRows(db: database) == 0)
        
        guard let fileVersion = try DirectoryEntry.fileVersion(fileUUID: fileUUID1, db: database) else {
            XCTFail()
            return
        }
        XCTAssert(fileVersion == 0)
    }
    */
    
/*
    func testTestWithADeclaredFileWorks() throws {
        try runQueueTest(withDeclaredFiles: true)
    }

    func testTestWithNoDeclaredFileFails() throws {
        try runQueueTest(withDeclaredFiles: false)
    }
    
    func runQueueTest(withUploads: Bool) throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        let fileUUID1 = UUID()

        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, appMetaData: nil, changeResolverName: nil)

        let declarations = Set<FileDeclaration>([declaration1])
        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleTextFileURL))

        var uploadables = Set<FileUpload>()
        if withUploads {
            uploadables.insert(uploadable1)
        }
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        do {
            try syncServer.queue(uploads: uploadables, declaration: testObject)
        } catch let error {
            if withUploads {
                XCTFail("\(error)")
            }
            return
        }
        
        if !withUploads {
            XCTFail()
            return
        }

        waitForUploadsToComplete(numberUploads: 1)
        
        XCTAssert(try UploadFileTracker.numberRows(db: database) == 0)
        XCTAssert(try UploadObjectTracker.numberRows(db: database) == 0)
    }
    
    func testTestWithAnUploadWorks() throws {
        try runQueueTest(withUploads: true)
    }

    func testTestWithNoUploadsFails() throws {
        try runQueueTest(withUploads: false)
    }
    
    func runQueueTest(withDistinctUUIDsInUploads: Bool) throws {
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let uploadFileUUID2: UUID
        if withDistinctUUIDsInUploads {
            uploadFileUUID2 = fileUUID2
        }
        else {
            uploadFileUUID2 = fileUUID1
        }

        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, appMetaData: nil, changeResolverName: nil)
        let declaration2 = FileDeclaration(uuid: fileUUID2, mimeType: MimeType.text, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration1, declaration2])
        
        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleTextFileURL))
        let uploadable2 = FileUpload(uuid: uploadFileUUID2, dataSource: .immutable(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable1, uploadable2])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        do {
            try syncServer.queue(uploads: uploadables, declaration: testObject)
        } catch {
            if withDistinctUUIDsInUploads {
                XCTFail()
            }
            return
        }
        
        if !withDistinctUUIDsInUploads {
            XCTFail()
            return
        }
        
        waitForUploadsToComplete(numberUploads: 2)
        
        XCTAssert(try UploadFileTracker.numberRows(db: database) == 0)
        XCTAssert(try UploadObjectTracker.numberRows(db: database) == 0)
    }
    
    // 9/5/20; Getting https://github.com/SyncServerII/ServerMain/issues/5 with parallel uploads.
    func testQueueWithDistinctUUIDsInUploadsWorks() throws {
        try runQueueTest(withDistinctUUIDsInUploads: true)
    }
    
    func testQueueWithNonDistinctUUIDsInUploadsFails() throws {
        try runQueueTest(withDistinctUUIDsInUploads: false)
    }
    
    func runQueueTest(withDistinctUUIDsInDeclarations: Bool) throws {
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let declarationFileUUID2: UUID
        if withDistinctUUIDsInDeclarations {
            declarationFileUUID2 = fileUUID2
        }
        else {
            declarationFileUUID2 = fileUUID1
        }
        
        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, appMetaData: nil, changeResolverName: nil)
        let declaration2 = FileDeclaration(uuid: declarationFileUUID2, mimeType: MimeType.text, appMetaData: "Some stuff", changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration1, declaration2])
        
        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable1])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        do {
            try syncServer.queue(uploads: uploadables, declaration: testObject)
        } catch {
            if withDistinctUUIDsInDeclarations {
                XCTFail()
            }
            return
        }
        
        if !withDistinctUUIDsInDeclarations {
            XCTFail()
            return
        }
        
        waitForUploadsToComplete(numberUploads: 1)
        
        XCTAssert(try UploadFileTracker.numberRows(db: database) == 0)
        XCTAssert(try UploadObjectTracker.numberRows(db: database) == 0)
    }
    
    func testQueueWithDistinctUUIDsInDeclarationsWorks() throws {
        try runQueueTest(withDistinctUUIDsInDeclarations: true)
    }
    
    func testQueueWithNonDistinctUUIDsInDeclarationsFails() throws {
        try runQueueTest(withDistinctUUIDsInDeclarations: false)
    }
    
    func testQueueObjectNotYetRegisteredWorks() throws {
        let fileUUID = UUID()
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        let declaration = FileDeclaration(uuid: fileUUID, mimeType: MimeType.text, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration])
        
        let uploadable = FileUpload(uuid: fileUUID, dataSource: .copy(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        try syncServer.queue(uploads: uploadables, declaration: testObject)
        
        let obj = try DeclaredObjectModel.lookupDeclarableObject(fileGroupUUID: testObject.declObjectId, db: database)
        XCTAssert(obj.declCompare(to: testObject))
        
        let count1 = try DeclaredObjectModel.numberRows(db: database,
            where: testObject.declObjectId == DeclaredObjectModel.fileGroupUUIDField.description)
        XCTAssert(count1 == 1)
        
        let count2 = try DeclaredFileModel.numberRows(db: database, where: testObject.declObjectId == DeclaredFileModel.fileGroupUUIDField.description)
        XCTAssert(count2 == 1)
        
        waitForUploadsToComplete(numberUploads: 1)
        
        guard let fileVersion = try DirectoryEntry.fileVersion(fileUUID: fileUUID, db: database) else {
            XCTFail()
            return
        }
        XCTAssert(fileVersion == 0)
    }
    
    // Other declared object(s) present, but give the wrong id
    func testLookupWithWrongObjectId() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        let fileUUID = UUID()
        let declaration = FileDeclaration(uuid: fileUUID, mimeType: MimeType.text, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration])
        let uploadable = FileUpload(uuid: fileUUID, dataSource: .copy(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        try syncServer.queue(uploads: uploadables, declaration: testObject)
        
        waitForUploadsToComplete(numberUploads: 1)

        do {
            let _ = try DeclaredObjectModel.lookupDeclarableObject(fileGroupUUID: UUID(), db: database)
        } catch let error {
            guard let error = error as? DatabaseModelError else {
                XCTFail()
                return
            }
            XCTAssert(error == DatabaseModelError.noObject)
            return
        }
        
        XCTFail()
    }
    
    func testQueueObjectAlreadyRegisteredWorks() throws {
        let fileUUID = UUID()
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        var queuedCount = 0
        handlers.extras.uploadQueued = { _ in
            queuedCount += 1
        }

        let declaration = FileDeclaration(uuid: fileUUID, mimeType: MimeType.text, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration])
        
        let uploadable = FileUpload(uuid: fileUUID, dataSource: .copy(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        try syncServer.queue(uploads: uploadables, declaration: testObject)
        XCTAssert(queuedCount == 0)

        // This second one should work also-- but not trigger an upload-- because its for the same file group as the immediately prior `queue`. i.e., the active upload.
        try syncServer.queue(uploads: uploadables, declaration: testObject)
        // Can't do this yet because of async delegate calls.
        // XCTAssert(queuedCount == 1, "\(queuedCount)")

        let count = try DeclaredObjectModel.numberRows(db: database,
            where: testObject.declObjectId == DeclaredObjectModel.fileGroupUUIDField.description)
        XCTAssert(count == 1)

        let count2 = try DeclaredFileModel.numberRows(db: database, where: testObject.declObjectId == DeclaredFileModel.fileGroupUUIDField.description)
        XCTAssert(count2 == 1)
        
        waitForUploadsToComplete(numberUploads: 1)
        XCTAssert(queuedCount == 1, "\(queuedCount)")

        // Until I get the second tier queued uploads working, need to remove the remaining non-uploaded file to not get a test failure.
        guard let tracker = try UploadFileTracker.fetchSingleRow(db: database, where: fileUUID == UploadFileTracker.fileUUIDField.description),
            let url = tracker.localURL else {
            XCTFail()
            return
        }
        
        try FileManager.default.removeItem(at: url)
    }
    
    func runUploadFile(differentFromDeclaredFile:Bool) throws {
        let fileUUID1 = UUID()
        let fileUUID2: UUID
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        if differentFromDeclaredFile {
            fileUUID2 = UUID()
        }
        else {
            fileUUID2 = fileUUID1
        }
        
        let declaration = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration])
        
        let uploadable = FileUpload(uuid: fileUUID2, dataSource: .copy(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        do {
            try syncServer.queue(uploads: uploadables, declaration: testObject)
        } catch {
            if !differentFromDeclaredFile {
                XCTFail()
            }
            return
        }
        
        if differentFromDeclaredFile {
            XCTFail()
            return
        }
        
        waitForUploadsToComplete(numberUploads: 1)
    }
    
    func testUploadFileWithUUIDDifferentFromDeclaredFileFails() throws {
        try runUploadFile(differentFromDeclaredFile:true)
    }
    
    func testUploadFileWithUUIDSameAsDeclaredFileWorks() throws {
        try runUploadFile(differentFromDeclaredFile:false)
    }

    func runUploadFileAfterInitialQueue(differentFromDeclaredFile:Bool) throws {
        let fileUUID1 = UUID()
        let fileUUID2:UUID
        
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        if differentFromDeclaredFile {
            fileUUID2 = UUID()
        }
        else {
            fileUUID2 = fileUUID1
        }
        
        let declaration = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration])
        
        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleTextFileURL))
        let uploadables1 = Set<FileUpload>([uploadable1])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)

        try syncServer.queue(uploads: uploadables1, declaration: testObject)

        let uploadable2 = FileUpload(uuid: fileUUID2, dataSource: .copy(exampleTextFileURL))
        let uploadables2 = Set<FileUpload>([uploadable2])
        
        do {
            try syncServer.queue(uploads: uploadables2, declaration: testObject)
        } catch {
            if !differentFromDeclaredFile {
                XCTFail()
            }
            
            waitForUploadsToComplete(numberUploads: 1)
            return
        }
        
        if differentFromDeclaredFile {
            XCTFail()
            return
        }
        
        waitForUploadsToComplete(numberUploads: 1)
    }
    
    func testUploadFileDifferentFromDeclaredFileWithExistingRegistrationFails() throws {
        try runUploadFileAfterInitialQueue(differentFromDeclaredFile:true)
    }
    
    func testUploadFileSameAsDeclaredFileWithExistingRegistrationWorks() throws {
        try runUploadFileAfterInitialQueue(differentFromDeclaredFile:true)
    }
    
    func testQueueWithExistingDeferredUpload() throws {
        var count = 0
        
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        handlers.extras.uploadQueued = { _ in
            count += 1
        }
        
        let fileUUID = UUID()
        
        let declaration = FileDeclaration(uuid: fileUUID, mimeType: MimeType.text, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration])
        
        let uploadable = FileUpload(uuid: fileUUID, dataSource: .copy(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)

        try syncServer.queue(uploads: uploadables, declaration: testObject)
        XCTAssert(count == 0, "\(count)")
        
        try syncServer.queue(uploads: uploadables, declaration: testObject)
        
        waitForUploadsToComplete(numberUploads: 1)
        XCTAssert(count == 1, "\(count)")

        // Until I get the second tier queued uploads working, need to remove the remaining non-uploaded file to not get a test failure.
        guard let tracker = try UploadFileTracker.fetchSingleRow(db: database, where: fileUUID == UploadFileTracker.fileUUIDField.description),
            let url = tracker.localURL else {
            XCTFail()
            return
        }
        
        try FileManager.default.removeItem(at: url)
    }
    
    func testQueueSingleImageFile() throws {
        let fileUUID1 = UUID()
        
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.jpeg, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration1])
        
        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleImageFileURL))
        let uploadables = Set<FileUpload>([uploadable1])

        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        try syncServer.queue(uploads: uploadables, declaration: testObject)
        
        waitForUploadsToComplete(numberUploads: 1)
    }

    func runQueueTest(withObjectType: Bool) throws {
        let fileUUID1 = UUID()
        
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, appMetaData: nil, changeResolverName: nil)

        let declarations = Set<FileDeclaration>([declaration1])
        
        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable1])
        
        var objectType: String?
        if withObjectType {
            objectType = "Foo"
        }

        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: objectType, sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        do {
            try syncServer.queue(uploads: uploadables, declaration: testObject)
        } catch let error {
            if withObjectType {
                XCTFail("\(error)")
            }
            return
        }
        
        if !withObjectType {
            XCTFail()
            return
        }
        
        waitForUploadsToComplete(numberUploads: 1)
        
        XCTAssert(try UploadFileTracker.numberRows(db: database) == 0)
        XCTAssert(try UploadObjectTracker.numberRows(db: database) == 0)
        
        guard let fileVersion = try DirectoryEntry.fileVersion(fileUUID: fileUUID1, db: database) else {
            XCTFail()
            return
        }
        XCTAssert(fileVersion == 0)
    }
    
    func testQueueWithObjectTypeWorks() throws {
        try runQueueTest(withObjectType: true)
    }
    
    func testQueueWithoutObjectTypeFails() throws {
        try runQueueTest(withObjectType: false)
    }
    
    func testUploadDeletedFileFails() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let localFile = Self.exampleTextFileURL
        
        let declaration = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        guard declaration.declaredFiles.count == 1,
            let declaredFile = declaration.declaredFiles.first else {
            XCTFail()
            return
        }
        
        try delete(object: declaration)
        
        // Technically, this is wrong. Because we're trying to upload v1 of a file that doesn't have a change resolver. But the failure will be detected before that.
        let uploadable1 = FileUpload(uuid: declaredFile.uuid, dataSource: .copy(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable1])
        
        do {
            try syncServer.queue(uploads: uploadables, declaration: declaration)
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
*/
}
