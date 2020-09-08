import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn

class UploadQueueTests_TwoObjectDeclarations: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests {
    var deviceUUID: UUID!
    var hashingManager: HashingManager!
    var uploadCompletedHandler: ((Swift.Result<UploadFileResult, Error>) -> ())?
    var downloadCompletedHandler: ((Swift.Result<DownloadFileResult, Error>) -> ())?
    
    var api: ServerAPI!
    var syncServer: SyncServer!
    var uploadQueued: ((SyncServer, _ syncObjectId: UUID) -> ())?
    var uploadStarted: ((SyncServer, _ deferredUploadId:Int64) -> ())?
    var uploadCompleted: ((SyncServer, UploadFileResult) -> ())?
    var deferredUploadsCompleted: ((SyncServer, _ count: Int)-> ())?
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
        XCTAssert(filePaths.count == 0)
    }
    
    func testQueueObject1FollowedByQueueObject2UploadsBoth() throws {
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()

        let sharingGroupUUID = try getSharingGroupUUID()

        // First object
        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations1 = Set<FileDeclaration>([declaration1])
        
        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleTextFileURL))
        let uploadables1 = Set<FileUpload>([uploadable1])

        let testObject1 = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations1)
        
        try syncServer.queue(declaration: testObject1, uploads: uploadables1)
        
        // Second object
        let declaration2 = FileDeclaration(uuid: fileUUID2, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations2 = Set<FileDeclaration>([declaration2])
        
        let uploadable2 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleTextFileURL))
        let uploadables2 = Set<FileUpload>([uploadable2])

        let testObject2 = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations2)
        
        try syncServer.queue(declaration: testObject2, uploads: uploadables2)

        waitForUploadsToComplete(numberUploads: 2)
        
        XCTAssert(try UploadFileTracker.numberRows(db: database) == 0)
        XCTAssert(try UploadObjectTracker.numberRows(db: database) == 0)
        XCTAssert(try DirectoryEntry.numberRows(db: database) == 2)
    }
}

extension UploadQueueTests_TwoObjectDeclarations: SyncServerCredentials {
    func credentialsForServerRequests(_ syncServer: SyncServer) throws -> GenericCredentials {
        return user.credentials
    }
}

extension UploadQueueTests_TwoObjectDeclarations: SyncServerDelegate {
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
    
    func deferredUploadsCompleted(_ syncServer: SyncServer, numberCompleted: Int) {
        deferredUploadsCompleted?(syncServer, numberCompleted)
    }
}
