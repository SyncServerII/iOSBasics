import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared

struct TestUploadable: UploadableFile {
    let uuid: UUID
    let url: URL
    let persistence: LocalPersistence
}

struct TestDeclaration: FileDeclaration {
    let uuid: UUID
    let mimeType: MimeType
    let appMetaData: String?
    let changeResolverName: String?
}

struct TestObject: DeclaredObject {
    // An id for this SyncedObject. This is required because we're organizing SyncObject's around these UUID's. AKA, syncObjectId
    let fileGroupUUID: UUID
    
    // The type of object that this collection of files is representing.
    // E.g., a Neebla image or Neebla URL as above.
    let objectType: String

    // An id for the group of users that have access to this SyncedObject
    let sharingGroupUUID: UUID
    
    let declaredFiles: Set<TestDeclaration>
}

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
        let declaration = TestDeclaration(uuid: UUID(), mimeType: MimeType.text, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<TestDeclaration>(arrayLiteral: declaration)
        let uploadable = TestUploadable(uuid: UUID(), url: URL(fileURLWithPath: "http://cprince.com"), persistence: .copy)
        let uploadables = Set<TestUploadable>(arrayLiteral: uploadable)
        
        let testObject = TestObject(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: UUID(), declaredFiles: declarations)
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
