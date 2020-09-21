
import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn

class FilesNeedingDeletionTests: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, Delegate, SyncServerTests {
    var deviceUUID: UUID!
    var hashingManager: HashingManager!
    var api: ServerAPI!
    var syncServer: SyncServer!
    var handlers = DelegateHandlers()
    var database: Connection!
    var config:Configuration!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        handlers = DelegateHandlers()
        handlers.user = try dropboxUser()
        deviceUUID = UUID()
        database = try Connection(.inMemory)
        hashingManager = HashingManager()
        try hashingManager.add(hashing: handlers.user.hashing)
        let serverURL = URL(string: Self.baseURL())!
        config = Configuration(appGroupIdentifier: nil, sqliteDatabasePath: "", serverURL: serverURL, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, configuration: config)
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

    func testNoFilesNeedingDeletion() throws {
        let objects = try syncServer.objectsNeedingDeletion()
        XCTAssert(objects.count == 0)
    }
    
    func testOneObjectNeedingDeletion() throws {
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
        
        // Reset the database show a state *as if* another client instance had done the upload/deleteion.
        database = try Connection(.inMemory)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, configuration: config)
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        
        try sync(withSharingGroupUUID: sharingGroupUUID)
        
        // As synced both deletion flags will be set to true; need the local one set to false for test.
        guard let entry = try DirectoryEntry.fetchSingleRow(db: database, where: DirectoryEntry.fileUUIDField.description == declaredFile.uuid) else {
            XCTFail()
            return
        }
        
        try entry.update(setters:
            DirectoryEntry.deletedLocallyField.description <- false)
        
        let objectsToDelete = try syncServer.objectsNeedingDeletion()
        guard objectsToDelete.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(objectsToDelete[0].declCompare(to: declaration))
    }
    
    func testTwoObjectsNeedingDeletion() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let localFile = Self.exampleTextFileURL
        
        let declaration1 = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        guard declaration1.declaredFiles.count == 1,
            let declaredFile1 = declaration1.declaredFiles.first else {
            XCTFail()
            return
        }
        
        let declaration2 = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        guard declaration2.declaredFiles.count == 1,
            let declaredFile2 = declaration2.declaredFiles.first else {
            XCTFail()
            return
        }
        
        try delete(object: declaration1)
        try delete(object: declaration2)

        // Reset the database show a state *as if* another client instance had done the upload/deleteion.
        database = try Connection(.inMemory)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, configuration: config)
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        
        try sync(withSharingGroupUUID: sharingGroupUUID)
        
        // As synced both deletion flags will be set to true; need the local one set to false for test.
        guard let entry1 = try DirectoryEntry.fetchSingleRow(db: database, where: DirectoryEntry.fileUUIDField.description == declaredFile1.uuid) else {
            XCTFail()
            return
        }
        
        try entry1.update(setters:
            DirectoryEntry.deletedLocallyField.description <- false)
            
        guard let entry2 = try DirectoryEntry.fetchSingleRow(db: database, where: DirectoryEntry.fileUUIDField.description == declaredFile2.uuid) else {
            XCTFail()
            return
        }
        
        try entry2.update(setters:
            DirectoryEntry.deletedLocallyField.description <- false)
            
        let objectsToDelete = try syncServer.objectsNeedingDeletion()
        guard objectsToDelete.count == 2 else {
            XCTFail()
            return
        }
        
        let filter1 = objectsToDelete.filter {$0.fileGroupUUID == declaration1.fileGroupUUID}
        let filter2 = objectsToDelete.filter {$0.fileGroupUUID == declaration2.fileGroupUUID}
        guard filter1.count == 1, filter2.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(filter1[0].declCompare(to: declaration1))
        XCTAssert(filter2[0].declCompare(to: declaration2))
    }
    
    func testDeleteUndeclaredObjectFails() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()

        let declaration1 = FileDeclaration(uuid: UUID(), mimeType: MimeType.text, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration1])

        let object = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        do {
            try syncServer.markAsDeleted(object: object)
        } catch let error {
            guard let error = error as? DatabaseModelError else {
                XCTFail()
                return
            }
            
            XCTAssert(DatabaseModelError.noObject == error)
        }
    }
    
    func testTwoObjectsNeedingDeletionMarkAsDeleted() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let localFile = Self.exampleTextFileURL
        
        let declaration1 = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        guard declaration1.declaredFiles.count == 1,
            let declaredFile1 = declaration1.declaredFiles.first else {
            XCTFail()
            return
        }
        
        let declaration2 = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        guard declaration2.declaredFiles.count == 1,
            let declaredFile2 = declaration2.declaredFiles.first else {
            XCTFail()
            return
        }

        try delete(object: declaration1)
        try delete(object: declaration2)

        // Reset the database show a state *as if* another client instance had done the upload/deleteion.
        database = try Connection(.inMemory)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, configuration: config)
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        
        try sync(withSharingGroupUUID: sharingGroupUUID)
        
        // As synced both deletion flags will be set to true; need the local one set to false for test.
        guard let entry1 = try DirectoryEntry.fetchSingleRow(db: database, where: DirectoryEntry.fileUUIDField.description == declaredFile1.uuid) else {
            XCTFail()
            return
        }
        
        try entry1.update(setters:
            DirectoryEntry.deletedLocallyField.description <- false)
            
        guard let entry2 = try DirectoryEntry.fetchSingleRow(db: database, where: DirectoryEntry.fileUUIDField.description == declaredFile2.uuid) else {
            XCTFail()
            return
        }
        
        try entry2.update(setters:
            DirectoryEntry.deletedLocallyField.description <- false)
            
        let objectsToDelete = try syncServer.objectsNeedingDeletion()
        guard objectsToDelete.count == 2 else {
            XCTFail()
            return
        }
        
        let filter1 = objectsToDelete.filter {$0.fileGroupUUID == declaration1.fileGroupUUID}
        let filter2 = objectsToDelete.filter {$0.fileGroupUUID == declaration2.fileGroupUUID}
        guard filter1.count == 1, filter2.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(filter1[0].declCompare(to: declaration1))
        XCTAssert(filter2[0].declCompare(to: declaration2))
        
        try syncServer.markAsDeleted(object: declaration1)
        
        let objectsToDelete2 = try syncServer.objectsNeedingDeletion()
        guard objectsToDelete2.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(objectsToDelete2[0].declCompare(to: declaration2))
        
        try syncServer.markAsDeleted(object: declaration2)
        
        let objectsToDelete3 = try syncServer.objectsNeedingDeletion()
        guard objectsToDelete3.count == 0 else {
            XCTFail()
            return
        }
    }
}
