import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn

class UploadQueueTests_SingleObjectDeclaration: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests {
    var deviceUUID: UUID!
    var hashingManager: HashingManager!
    var uploadCompletedHandler: ((Swift.Result<UploadFileResult, Error>) -> ())?
    var downloadCompletedHandler: ((Swift.Result<DownloadFileResult, Error>) -> ())?
    
    var api: ServerAPI!
    var syncServer: SyncServer!
    var uploadQueued: ((SyncServer, _ syncObjectId: UUID) -> ())?
    var uploadStarted: ((SyncServer, _ deferredUploadId:Int64) -> ())?
    var uploadCompleted: ((SyncServer, UploadResult) -> ())?
    var error:((SyncServer, Error?) -> ())?
    var user: TestUser!
    var database: Connection!
    var config:Configuration!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        user = try dropboxUser()
        deviceUUID = UUID()
        database = try Connection(.inMemory)
        hashingManager = HashingManager()
        try hashingManager.add(hashing: user.hashing)
        let serverURL = URL(string: Self.baseURL())!
        config = Configuration(appGroupIdentifier: nil, sqliteDatabasePath: "", serverURL: serverURL, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, configuration: config)
        api = syncServer.api
        uploadQueued = nil
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        
        _ = user.removeUser()
        guard user.addUser() else {
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
    
    // No declared objects present
    func testLookupWithNoObject() {
        do {
            let _ = try DeclaredObjectModel.lookupDeclarableObject(declObjectId: UUID(), db: database)
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
    
    func runQueueTest(withDeclaredFiles: Bool) throws {
        let fileUUID1 = UUID()
        
        let sharingGroupUUID = try getSharingGroupUUID()

        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)

        var declarations = Set<FileDeclaration>()
        if withDeclaredFiles {
            declarations.insert(declaration1)
        }
        
        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable1])

        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        do {
            try syncServer.queueUploads(declaration: testObject, uploads: uploadables)
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
    
    func testTestWithADeclaredFileWorks() throws {
        try runQueueTest(withDeclaredFiles: true)
    }

    func testTestWithNoDeclaredFileFails() throws {
        try runQueueTest(withDeclaredFiles: false)
    }
    
    func runQueueTest(withUploads: Bool) throws {
        let sharingGroupUUID = try getSharingGroupUUID()

        let fileUUID1 = UUID()

        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)

        let declarations = Set<FileDeclaration>([declaration1])
        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleTextFileURL))

        var uploadables = Set<FileUpload>()
        if withUploads {
            uploadables.insert(uploadable1)
        }
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        do {
            try syncServer.queueUploads(declaration: testObject, uploads: uploadables)
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
        
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let uploadFileUUID2: UUID
        if withDistinctUUIDsInUploads {
            uploadFileUUID2 = fileUUID2
        }
        else {
            uploadFileUUID2 = fileUUID1
        }

        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declaration2 = FileDeclaration(uuid: fileUUID2, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration1, declaration2])
        
        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleTextFileURL))
        let uploadable2 = FileUpload(uuid: uploadFileUUID2, dataSource: .immutable(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable1, uploadable2])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        do {
            try syncServer.queueUploads(declaration: testObject, uploads: uploadables)
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
        
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let declarationFileUUID2: UUID
        if withDistinctUUIDsInDeclarations {
            declarationFileUUID2 = fileUUID2
        }
        else {
            declarationFileUUID2 = fileUUID1
        }
        
        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declaration2 = FileDeclaration(uuid: declarationFileUUID2, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: "Some stuff", changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration1, declaration2])
        
        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable1])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        do {
            try syncServer.queueUploads(declaration: testObject, uploads: uploadables)
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
        let sharingGroupUUID = try getSharingGroupUUID()

        let declaration = FileDeclaration(uuid: fileUUID, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration])
        
        let uploadable = FileUpload(uuid: fileUUID, dataSource: .copy(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        try syncServer.queueUploads(declaration: testObject, uploads: uploadables)
        
        let obj = try DeclaredObjectModel.lookupDeclarableObject(declObjectId: testObject.declObjectId, db: database)
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
        let sharingGroupUUID = try getSharingGroupUUID()
        let fileUUID = UUID()
        let declaration = FileDeclaration(uuid: fileUUID, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration])
        let uploadable = FileUpload(uuid: fileUUID, dataSource: .copy(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        try syncServer.queueUploads(declaration: testObject, uploads: uploadables)
        
        waitForUploadsToComplete(numberUploads: 1)

        do {
            let _ = try DeclaredObjectModel.lookupDeclarableObject(declObjectId: UUID(), db: database)
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
        let sharingGroupUUID = try getSharingGroupUUID()
        
        var queuedCount = 0
        uploadQueued = { _, syncObjectId in
            queuedCount += 1
        }

        let declaration = FileDeclaration(uuid: fileUUID, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration])
        
        let uploadable = FileUpload(uuid: fileUUID, dataSource: .copy(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        try syncServer.queueUploads(declaration: testObject, uploads: uploadables)
        XCTAssert(queuedCount == 0)

        // This second one should work also-- but not trigger an upload-- because its for the same file group as the immediately prior `queue`. i.e., the active upload.
        try syncServer.queueUploads(declaration: testObject, uploads: uploadables)
        // Can't do this yet because of async delegate calls.
        // XCTAssert(queuedCount == 1)

        let count = try DeclaredObjectModel.numberRows(db: database,
            where: testObject.declObjectId == DeclaredObjectModel.fileGroupUUIDField.description)
        XCTAssert(count == 1)
        
        let count2 = try DeclaredFileModel.numberRows(db: database, where: testObject.declObjectId == DeclaredFileModel.fileGroupUUIDField.description)
        XCTAssert(count2 == 1)
        
        waitForUploadsToComplete(numberUploads: 1)
        XCTAssert(queuedCount == 1)
        
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
        let sharingGroupUUID = try getSharingGroupUUID()

        if differentFromDeclaredFile {
            fileUUID2 = UUID()
        }
        else {
            fileUUID2 = fileUUID1
        }
        
        let declaration = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration])
        
        let uploadable = FileUpload(uuid: fileUUID2, dataSource: .copy(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        do {
            try syncServer.queueUploads(declaration: testObject, uploads: uploadables)
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

        let sharingGroupUUID = try getSharingGroupUUID()

        if differentFromDeclaredFile {
            fileUUID2 = UUID()
        }
        else {
            fileUUID2 = fileUUID1
        }
        
        let declaration = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration])
        
        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleTextFileURL))
        let uploadables1 = Set<FileUpload>([uploadable1])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)

        try syncServer.queueUploads(declaration: testObject, uploads: uploadables1)

        let uploadable2 = FileUpload(uuid: fileUUID2, dataSource: .copy(exampleTextFileURL))
        let uploadables2 = Set<FileUpload>([uploadable2])
        
        do {
            try syncServer.queueUploads(declaration: testObject, uploads: uploadables2)
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
        
        uploadQueued = { syncServer, objectId in
            count += 1
        }
        
        let sharingGroupUUID = try getSharingGroupUUID()
        let fileUUID = UUID()
        
        let declaration = FileDeclaration(uuid: fileUUID, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration])
        
        let uploadable = FileUpload(uuid: fileUUID, dataSource: .copy(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)

        try syncServer.queueUploads(declaration: testObject, uploads: uploadables)
        XCTAssert(count == 0, "\(count)")
        
        try syncServer.queueUploads(declaration: testObject, uploads: uploadables)
        
        // Can't do this yet because of asynchronous delegate callbacks
        // XCTAssert(count == 1, "\(count)")
        
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
        
        let sharingGroupUUID = try getSharingGroupUUID()

        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.jpeg, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration1])
        
        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleImageFileURL))
        let uploadables = Set<FileUpload>([uploadable1])

        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        try syncServer.queueUploads(declaration: testObject, uploads: uploadables)
        
        waitForUploadsToComplete(numberUploads: 1)
    }

    func runQueueTest(withObjectType: Bool) throws {
        let fileUUID1 = UUID()
        
        let sharingGroupUUID = try getSharingGroupUUID()

        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)

        let declarations = Set<FileDeclaration>([declaration1])
        
        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable1])
        
        var objectType: String?
        if withObjectType {
            objectType = "Foo"
        }

        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: objectType, sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        do {
            try syncServer.queueUploads(declaration: testObject, uploads: uploadables)
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
}

extension UploadQueueTests_SingleObjectDeclaration: SyncServerCredentials {
    func credentialsForServerRequests(_ syncServer: SyncServer) throws -> GenericCredentials {
        return user.credentials
    }
}

extension UploadQueueTests_SingleObjectDeclaration: SyncServerDelegate {
    func error(_ syncServer: SyncServer, error: Error?) {
        XCTFail("\(String(describing: error))")
        self.error?(syncServer, error)
    }

    func syncCompleted(_ syncServer: SyncServer, result: SyncResult) {
    }
    
    func downloadCompleted(_ syncServer: SyncServer, declObjectId: UUID) {
    }
    
    // A uuid that was initially generated on the client
    func uuidCollision(_ syncServer: SyncServer, type: UUIDCollisionType, from: UUID, to: UUID) {
    }
    
    func uploadQueued(_ syncServer: SyncServer, declObjectId: UUID) {
        self.uploadQueued?(syncServer, declObjectId)
    }
    
    func uploadStarted(_ syncServer: SyncServer, deferredUploadId:Int64) {
        uploadStarted?(syncServer, deferredUploadId)
    }
    
    func uploadCompleted(_ syncServer: SyncServer, result: UploadResult) {
        uploadCompleted?(syncServer, result)
    }
    
    func deferredCompleted(_ syncServer: SyncServer, operation: DeferredOperation, numberCompleted: Int) {
    }
    
    func deletionCompleted(_ syncServer: SyncServer) {
    }
    
    func downloadDeletion(_ syncServer: SyncServer, details: DownloadDeletion) {
    }
}
