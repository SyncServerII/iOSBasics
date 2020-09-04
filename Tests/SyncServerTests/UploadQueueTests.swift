import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared

class UploadQueueTests: APITestCase, APITests {
    var db: Connection!
    var syncServer: SyncServer!
    
    override func setUpWithError() throws {
        db = try Connection(.inMemory)
        let hashingManager = HashingManager()
        let config = Configuration(appGroupIdentifier: nil, sqliteDatabasePath: "", serverURL: URL(fileURLWithPath: Self.baseURL()), minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName)
        syncServer = try SyncServer(hashingManager: hashingManager, db: db, configuration: config, delegate: self)
    }

    override func tearDownWithError() throws {
    }
    
    func testLookupWithNoObject() {
    }
    
    func testSyncObjectNotYetRegisteredWorks() throws {
        let declaration = FileDeclaration(uuid: UUID(), mimeType: MimeType.text, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>(arrayLiteral: declaration)
        let uploadable = FileUpload(uuid: UUID(), url: URL(fileURLWithPath: "http://cprince.com"), persistence: .copy)
        let uploadables = Set<FileUpload>(arrayLiteral: uploadable)
        
        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: UUID(), declaredFiles: declarations)
        try syncServer.queue(declaration: testObject, uploads: uploadables)
        
        let obj = try syncServer.lookupDeclObject(declObjectId: testObject.declObjectId)
        XCTAssert(obj.declCompare(to: testObject))
    }
    
    func testSyncObjectAlreadyRegisteredWorks() {
    }
    

}

extension UploadQueueTests: SyncServerDelegate {
    func syncCompleted(_ syncServer: SyncServer) {
    }
    
    func downloadCompleted(_ syncServer: SyncServer, syncObjectId: UUID) {
    }
    
    // A uuid that was initially generated on the client
    func uuidCollision(_ syncServer: SyncServer, type: UUIDCollisionType, from: UUID, to: UUID) {
    }
}
