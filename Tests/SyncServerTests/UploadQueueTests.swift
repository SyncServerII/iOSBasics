import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn

class UploadQueueTests: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests {
    var deviceUUID: UUID!
    var hashingManager: HashingManager!
    var uploadCompletedHandler: ((Swift.Result<UploadFileResult, Error>) -> ())?
    var downloadCompletedHandler: ((Swift.Result<DownloadFileResult, Error>) -> ())?
    
    var api: ServerAPI!
    var syncServer: SyncServer!
    var uploadQueued: ((SyncServer, _ syncObjectId: UUID) -> ())?
    var uploadStarted: ((SyncServer, _ deferredUploadId:Int64) -> ())?
    var uploadCompleted: ((SyncServer, UploadFileResult) -> ())?
    var error:((SyncServer, Error?) -> ())?
    var user: TestUser!
    var database: Connection!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        user = try dropboxUser()
        deviceUUID = UUID()
        database = try Connection(.inMemory)
        hashingManager = HashingManager()
        try hashingManager.add(hashing: user.hashing)
        let serverURL = URL(string: Self.baseURL())!
        let config = Configuration(appGroupIdentifier: nil, sqliteDatabasePath: "", serverURL: serverURL, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, configuration: config)
        api = syncServer.api
        uploadQueued = nil
        syncServer.delegate = self
        _ = user.removeUser()
        guard user.addUser() else {
            throw SyncServerError.internalError("Could not add user")
        }
    }

    override func tearDownWithError() throws {
    }
    
    func waitForUploadsToComplete(numberUploads: Int) {
        var count = 0
        let exp = expectation(description: "exp")
        uploadCompleted = { _, result in
            count += 1

            switch result {
            case .gone:
                XCTFail()
            case .success(creationDate: let creationDate, updateDate: _, uploadsFinished: let allUploadsFinished, deferredUploadId: let deferredUploadId):
                if count == numberUploads {
                    XCTAssert(allUploadsFinished == .v0UploadsFinished, "\(allUploadsFinished)")
                }
                XCTAssertNotNil(creationDate)
                XCTAssertNil(deferredUploadId)
            }
            
            if count == numberUploads {
                exp.fulfill()
            }
        }
        error = { _, result in
            XCTFail()
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    // No declared objects present
    func testLookupWithNoObject() {
        do {
            let _ = try syncServer.lookupDeclObject(declObjectId: UUID())
        } catch let error {
            guard let error = error as? SyncServerError else {
                XCTFail()
                return
            }
            XCTAssert(error == SyncServerError.noObject)
            return
        }
        
        XCTFail()
    }
    
    func getSharingGroupUUID() throws -> UUID {
        guard let serverIndex = getIndex(sharingGroupUUID: nil),
            serverIndex.sharingGroups.count > 0,
            let sharingGroupUUIDString = serverIndex.sharingGroups[0].sharingGroupUUID,
            let sharingGroupUUID = UUID(uuidString: sharingGroupUUIDString) else {
            throw SyncServerError.internalError("Could not get sharing group UUID")
        }
        return sharingGroupUUID
    }
    
    func runQueueTest(withDeclaredFiles: Bool) throws {
        let fileUUID1 = UUID()
        
        let sharingGroupUUID = try getSharingGroupUUID()

        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)

        var declarations = Set<FileDeclaration>()
        if withDeclaredFiles {
            declarations.insert(declaration1)
        }
        
        let uploadable1 = FileUpload(uuid: fileUUID1, url: exampleTextFileURL, persistence: .copy)
        let uploadables = Set<FileUpload>([uploadable1])

        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        do {
            try syncServer.queue(declaration: testObject, uploads: uploadables)
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
        let uploadable1 = FileUpload(uuid: fileUUID1, url: exampleTextFileURL, persistence: .copy)

        var uploadables = Set<FileUpload>()
        if withUploads {
            uploadables.insert(uploadable1)
        }
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        do {
            try syncServer.queue(declaration: testObject, uploads: uploadables)
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
        
        let uploadable1 = FileUpload(uuid: fileUUID1, url: exampleTextFileURL, persistence: .copy)
        let uploadable2 = FileUpload(uuid: uploadFileUUID2, url: exampleTextFileURL, persistence: .immutable)
        let uploadables = Set<FileUpload>([uploadable1, uploadable2])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        do {
            try syncServer.queue(declaration: testObject, uploads: uploadables)
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
        
        let uploadable1 = FileUpload(uuid: fileUUID1, url: exampleTextFileURL, persistence: .copy)
        let uploadables = Set<FileUpload>([uploadable1])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        do {
            try syncServer.queue(declaration: testObject, uploads: uploadables)
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
        let uploadable = FileUpload(uuid: fileUUID, url: exampleTextFileURL, persistence: .copy)
        let uploadables = Set<FileUpload>([uploadable])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        try syncServer.queue(declaration: testObject, uploads: uploadables)
        
        let obj = try syncServer.lookupDeclObject(declObjectId: testObject.declObjectId)
        XCTAssert(obj.declCompare(to: testObject))
        
        let count1 = try DeclaredObjectModel.numberRows(db: database,
            where: testObject.declObjectId == DeclaredObjectModel.fileGroupUUIDField.description)
        XCTAssert(count1 == 1)
        
        let count2 = try DeclaredFileModel.numberRows(db: database, where: testObject.declObjectId == DeclaredFileModel.fileGroupUUIDField.description)
        XCTAssert(count2 == 1)
        
        waitForUploadsToComplete(numberUploads: 1)
    }
    
    // Other declared object(s) present, but give the wrong id
    func testLookupWithWrongObjectId() throws {
        let sharingGroupUUID = try getSharingGroupUUID()
        let fileUUID = UUID()
        let declaration = FileDeclaration(uuid: fileUUID, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration])
        let uploadable = FileUpload(uuid: fileUUID, url: exampleTextFileURL, persistence: .copy)
        let uploadables = Set<FileUpload>([uploadable])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        try syncServer.queue(declaration: testObject, uploads: uploadables)
        
        waitForUploadsToComplete(numberUploads: 1)

        do {
            let _ = try syncServer.lookupDeclObject(declObjectId: UUID())
        } catch let error {
            guard let error = error as? SyncServerError else {
                XCTFail()
                return
            }
            XCTAssert(error == SyncServerError.noObject)
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
        let uploadable = FileUpload(uuid: fileUUID, url: exampleTextFileURL, persistence: .copy)
        let uploadables = Set<FileUpload>([uploadable])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        try syncServer.queue(declaration: testObject, uploads: uploadables)
        XCTAssert(queuedCount == 0)

        // This second one should work also
        try syncServer.queue(declaration: testObject, uploads: uploadables)
        XCTAssert(queuedCount == 1)

        let count = try DeclaredObjectModel.numberRows(db: database,
            where: testObject.declObjectId == DeclaredObjectModel.fileGroupUUIDField.description)
        XCTAssert(count == 1)
        
        let count2 = try DeclaredFileModel.numberRows(db: database, where: testObject.declObjectId == DeclaredFileModel.fileGroupUUIDField.description)
        XCTAssert(count2 == 1)
        
        waitForUploadsToComplete(numberUploads: 1)
        XCTAssert(queuedCount == 1)
    }
    
    func testUploadFileDifferentFromDeclaredFileFails() throws {
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()
        let sharingGroupUUID = try getSharingGroupUUID()

        let declaration = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration])
        
        let uploadable = FileUpload(uuid: fileUUID2, url: exampleTextFileURL, persistence: .copy)
        let uploadables = Set<FileUpload>([uploadable])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        do {
            try syncServer.queue(declaration: testObject, uploads: uploadables)
        } catch {
            return
        }
        
        XCTFail()
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
        
        let uploadable = FileUpload(uuid: fileUUID2, url: exampleTextFileURL, persistence: .copy)
        let uploadables = Set<FileUpload>([uploadable])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        do {
            try syncServer.queue(declaration: testObject, uploads: uploadables)
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
    
    func testUploadFileWithIdDifferentFromDeclaredFileFails() throws {
        try runUploadFile(differentFromDeclaredFile:true)
    }
    
    func testUploadFileWithIdSameAsDeclaredFileWorks() throws {
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
        
        let uploadable1 = FileUpload(uuid: fileUUID1, url: exampleTextFileURL, persistence: .copy)
        let uploadables1 = Set<FileUpload>([uploadable1])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)

        try syncServer.queue(declaration: testObject, uploads: uploadables1)

        let uploadable2 = FileUpload(uuid: fileUUID2, url: exampleTextFileURL, persistence: .copy)
        let uploadables2 = Set<FileUpload>([uploadable2])
        
        do {
            try syncServer.queue(declaration: testObject, uploads: uploadables2)
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
        
        let uploadable = FileUpload(uuid: fileUUID, url: exampleTextFileURL, persistence: .copy)
        let uploadables = Set<FileUpload>([uploadable])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)

        try syncServer.queue(declaration: testObject, uploads: uploadables)
        XCTAssert(count == 0, "\(count)")
        
        try syncServer.queue(declaration: testObject, uploads: uploadables)
        XCTAssert(count == 1, "\(count)")
        
        waitForUploadsToComplete(numberUploads: 1)
    }
}

extension UploadQueueTests: SyncServerDelegate {
    func credentialsForServerRequests(_ syncServer: SyncServer) throws -> GenericCredentials {
        return user.credentials
    }
    
    func error(_ syncServer: SyncServer, error: Error?) {
        XCTFail("\(String(describing: error))")
        self.error?(syncServer, error)
    }

    func syncCompleted(_ syncServer: SyncServer) {
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
    
    func uploadCompleted(_ syncServer: SyncServer, result: UploadFileResult) {
        uploadCompleted?(syncServer, result)
    }
}
