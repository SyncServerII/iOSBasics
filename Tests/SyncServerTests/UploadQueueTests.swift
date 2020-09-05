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
        
        let exp = expectation(description: "exp")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            exp.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
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
        }
    }
    
    func testTestWithAnUploadWorks() throws {
        try runQueueTest(withUploads: true)
    }

    func testTestWithNoUploadsFails() throws {
        try runQueueTest(withUploads: false)
    }
    
    func runQueueTest(withDistinctUUIDsInUploads: Bool) {
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()
        
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
        let uploadable1 = FileUpload(uuid: fileUUID1, url: URL(fileURLWithPath: "http://cprince.com"), persistence: .copy)
        let uploadable2 = FileUpload(uuid: uploadFileUUID2, url: URL(fileURLWithPath: "http://cprince.com"), persistence: .immutable)

        let uploadables = Set<FileUpload>([uploadable1, uploadable2])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: UUID(), declaredFiles: declarations)
        
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
        }
    }
    
    func testQueueWithDistinctUUIDsInUploadsWorks() {
        runQueueTest(withDistinctUUIDsInUploads: true)
    }
    
    func testQueueWithNonDistinctUUIDsInUploadsFails() {
        runQueueTest(withDistinctUUIDsInUploads: false)
    }
    
    func runQueueTest(withDistinctUUIDsInDeclarations: Bool) {
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()
        
        let declarationFileUUID2: UUID
        if withDistinctUUIDsInDeclarations {
            declarationFileUUID2 = fileUUID2
        }
        else {
            declarationFileUUID2 = fileUUID1
        }

        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declaration2 = FileDeclaration(uuid: declarationFileUUID2, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)

        let declarations = Set<FileDeclaration>([declaration1, declaration2])
        let uploadable1 = FileUpload(uuid: fileUUID1, url: URL(fileURLWithPath: "http://cprince.com"), persistence: .copy)

        let uploadables = Set<FileUpload>([uploadable1])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: UUID(), declaredFiles: declarations)
        
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
        }
    }
    
    func testQueueWithDistinctUUIDsInDeclarationsWorks() {
        runQueueTest(withDistinctUUIDsInUploads: true)
    }
    
    func testQueueWithNonDistinctUUIDsInDeclarationsFails() {
        runQueueTest(withDistinctUUIDsInUploads: false)
    }
    
    func testQueueObjectNotYetRegisteredWorks() throws {
        let fileUUID = UUID()
        let declaration = FileDeclaration(uuid: fileUUID, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration])
        let uploadable = FileUpload(uuid: fileUUID, url: URL(fileURLWithPath: "http://cprince.com"), persistence: .copy)
        let uploadables = Set<FileUpload>([uploadable])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: UUID(), declaredFiles: declarations)
        try syncServer.queue(declaration: testObject, uploads: uploadables)
        
        let obj = try syncServer.lookupDeclObject(declObjectId: testObject.declObjectId)
        XCTAssert(obj.declCompare(to: testObject))
        
        let count1 = try DeclaredObjectModel.numberRows(db: database,
            where: testObject.declObjectId == DeclaredObjectModel.fileGroupUUIDField.description)
        XCTAssert(count1 == 1)
        
        let count2 = try DeclaredFileModel.numberRows(db: database, where: testObject.declObjectId == DeclaredFileModel.fileGroupUUIDField.description)
        XCTAssert(count2 == 1)
    }
    
    // Other declared object(s) present, but give the wrong id
    func testLookupWithWrongObjectId() throws {
        let fileUUID = UUID()
        let declaration = FileDeclaration(uuid: fileUUID, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration])
        let uploadable = FileUpload(uuid: fileUUID, url: URL(fileURLWithPath: "http://cprince.com"), persistence: .copy)
        let uploadables = Set<FileUpload>([uploadable])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: UUID(), declaredFiles: declarations)
        try syncServer.queue(declaration: testObject, uploads: uploadables)
        
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
        let declaration = FileDeclaration(uuid: fileUUID, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration])
        let uploadable = FileUpload(uuid: fileUUID, url: URL(fileURLWithPath: "http://cprince.com"), persistence: .copy)
        let uploadables = Set<FileUpload>([uploadable])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: UUID(), declaredFiles: declarations)
        try syncServer.queue(declaration: testObject, uploads: uploadables)
        
        // This second one should work also
        try syncServer.queue(declaration: testObject, uploads: uploadables)

        let count = try DeclaredObjectModel.numberRows(db: database,
            where: testObject.declObjectId == DeclaredObjectModel.fileGroupUUIDField.description)
        XCTAssert(count == 1)
        
        let count2 = try DeclaredFileModel.numberRows(db: database, where: testObject.declObjectId == DeclaredFileModel.fileGroupUUIDField.description)
        XCTAssert(count2 == 1)
    }
    
    func testUploadFileDifferentFromDeclaredFileFails() throws {
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()
        let declaration = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration])
        let uploadable = FileUpload(uuid: fileUUID2, url: URL(fileURLWithPath: "http://cprince.com"), persistence: .copy)
        let uploadables = Set<FileUpload>([uploadable])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: UUID(), declaredFiles: declarations)
        
        do {
            try syncServer.queue(declaration: testObject, uploads: uploadables)
        } catch {
            return
        }
        
        XCTFail()
    }
    
    func runUploadFile(differentFromDeclaredFile:Bool) {
        let fileUUID1 = UUID()
        let fileUUID2:UUID
        
        if differentFromDeclaredFile {
            fileUUID2 = UUID()
        }
        else {
            fileUUID2 = fileUUID1
        }
        
        let declaration = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration])
        let uploadable = FileUpload(uuid: fileUUID2, url: URL(fileURLWithPath: "http://cprince.com"), persistence: .copy)
        let uploadables = Set<FileUpload>([uploadable])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: UUID(), declaredFiles: declarations)
        
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
        }
    }
    
    func testUploadFileWithIdDifferentFromDeclaredFileFails() {
        runUploadFile(differentFromDeclaredFile:true)
    }
    
    func testUploadFileWithIdSameAsDeclaredFileWorks() {
        runUploadFile(differentFromDeclaredFile:false)
    }

    func runUploadFileAfterInitialQueue(differentFromDeclaredFile:Bool) throws {
        let fileUUID1 = UUID()
        let fileUUID2:UUID
        
        if differentFromDeclaredFile {
            fileUUID2 = UUID()
        }
        else {
            fileUUID2 = fileUUID1
        }
        
        let declaration = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration])
        let uploadable1 = FileUpload(uuid: fileUUID1, url: URL(fileURLWithPath: "http://cprince.com"), persistence: .copy)
        let uploadables1 = Set<FileUpload>([uploadable1])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: UUID(), declaredFiles: declarations)

        try syncServer.queue(declaration: testObject, uploads: uploadables1)

        let uploadable2 = FileUpload(uuid: fileUUID2, url: URL(fileURLWithPath: "http://cprince.com"), persistence: .copy)
        let uploadables2 = Set<FileUpload>([uploadable2])
        
        do {
            try syncServer.queue(declaration: testObject, uploads: uploadables2)
        } catch {
            if !differentFromDeclaredFile {
                XCTFail()
            }
            return
        }
        
        if differentFromDeclaredFile {
            XCTFail()
        }
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
        
        let fileUUID = UUID()
        
        let declaration = FileDeclaration(uuid: fileUUID, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration])
        
        let uploadable = FileUpload(uuid: fileUUID, url: URL(fileURLWithPath: "http://cprince.com"), persistence: .copy)
        let uploadables = Set<FileUpload>([uploadable])
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: UUID(), declaredFiles: declarations)

        try syncServer.queue(declaration: testObject, uploads: uploadables)
        XCTAssert(count == 0, "\(count)")
        
        try syncServer.queue(declaration: testObject, uploads: uploadables)
        XCTAssert(count == 1, "\(count)")
    }
}

extension UploadQueueTests: SyncServerDelegate {
    func credentialsForServerRequests(_ syncServer: SyncServer) throws -> GenericCredentials {
        return user.credentials
    }
    
    func error(_ syncServer: SyncServer, error: Error?) {
        XCTFail("\(String(describing: error))")
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
}
