
import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
import iOSShared
import iOSSignIn
@testable import TestsCommon

class FilesNeedingDeletionTests: XCTestCase, UserSetup, ServerBasics, TestFiles, APITests, Delegate, SyncServerTests {
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

    func testNoFilesNeedingDeletion() throws {
        let objects = try syncServer.objectsNeedingLocalDeletion()
        XCTAssert(objects.count == 0)
    }

    func testOneObjectNeedingDeletion() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let localFile = Self.exampleTextFileURL
        
        let (uploadableObject, example) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        guard uploadableObject.uploads.count == 1,
            let uploadFile = uploadableObject.uploads.first else {
            XCTFail()
            return
        }
        
        try delete(object: uploadableObject.fileGroupUUID)
        
        // Reset the database show a state *as if* another client instance had done the upload/deleteion.
        database = try Connection(.inMemory)
        let fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, configuration: config, signIns: fakeSignIns)
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        syncServer.helperDelegate = self
        handlers.objectType = { _, _ in
            return nil
        }
        
        try syncServer.register(object: example)

        try sync(withSharingGroupUUID: sharingGroupUUID)
        
        // As synced, both deletion flags will be set to true; need the local one set to false for test.
        guard let objectEntry = try DirectoryObjectEntry.fetchSingleRow(db: database, where: DirectoryObjectEntry.fileGroupUUIDField.description == uploadableObject.fileGroupUUID) else {
            XCTFail()
            return
        }
        
        guard let fileEntry = try DirectoryFileEntry.fetchSingleRow(db: database, where: DirectoryFileEntry.fileUUIDField.description == uploadFile.uuid) else {
            XCTFail()
            return
        }
        
        try objectEntry.update(setters:
            DirectoryObjectEntry.deletedLocallyField.description <- false)
        try fileEntry.update(setters:
            DirectoryFileEntry.deletedLocallyField.description <- false)
            
        let objectsToDelete = try syncServer.objectsNeedingLocalDeletion()
        guard objectsToDelete.count == 1 else {
            XCTFail("\(objectsToDelete.count)")
            return
        }
        
        XCTAssert(objectsToDelete[0] == uploadableObject.fileGroupUUID)
    }
    
    func testTwoObjectsNeedingDeletion() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let localFile = Self.exampleTextFileURL
        
        let (objectUpload1, example1) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        guard objectUpload1.uploads.count == 1,
            let uploadFile1 = objectUpload1.uploads.first else {
            XCTFail()
            return
        }
        
        let (objectUpload2, example2)  = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        guard objectUpload2.uploads.count == 1,
            let uploadFile2 = objectUpload2.uploads.first else {
            XCTFail()
            return
        }
        
        try delete(object: objectUpload1.fileGroupUUID)
        try delete(object: objectUpload2.fileGroupUUID)

        // Reset the database show a state *as if* another client instance had done the upload/deleteion.
        database = try Connection(.inMemory)
        let fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, configuration: config, signIns: fakeSignIns)
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        syncServer.helperDelegate = self
        handlers.objectType = { _, _ in
            return nil
        }
        
        try syncServer.register(object: example1)
        try syncServer.register(object: example2)
        
        try sync(withSharingGroupUUID: sharingGroupUUID)
        
        // As synced both deletion flags will be set to true; need the local one set to false for test.
        guard let fileEntry1 = try DirectoryFileEntry.fetchSingleRow(db: database, where: DirectoryFileEntry.fileUUIDField.description == uploadFile1.uuid) else {
            XCTFail()
            return
        }
        
        guard let objectEntry1 = try DirectoryObjectEntry.fetchSingleRow(db: database, where: DirectoryObjectEntry.fileGroupUUIDField.description == objectUpload1.fileGroupUUID) else {
            XCTFail()
            return
        }
        
        try fileEntry1.update(setters:
            DirectoryFileEntry.deletedLocallyField.description <- false)
        try objectEntry1.update(setters:
            DirectoryObjectEntry.deletedLocallyField.description <- false)
            
        guard let fileEntry2 = try DirectoryFileEntry.fetchSingleRow(db: database, where: DirectoryFileEntry.fileUUIDField.description == uploadFile2.uuid) else {
            XCTFail()
            return
        }
        
        guard let objectEntry2 = try DirectoryObjectEntry.fetchSingleRow(db: database, where: DirectoryObjectEntry.fileGroupUUIDField.description == objectUpload2.fileGroupUUID) else {
            XCTFail()
            return
        }
        
        try fileEntry2.update(setters:
            DirectoryFileEntry.deletedLocallyField.description <- false)
        try objectEntry2.update(setters:
            DirectoryObjectEntry.deletedLocallyField.description <- false)
            
        let objectsToDelete = try syncServer.objectsNeedingLocalDeletion()
        guard objectsToDelete.count == 2 else {
            XCTFail()
            return
        }
        
        let filter1 = objectsToDelete.filter {$0 == objectUpload1.fileGroupUUID}
        let filter2 = objectsToDelete.filter {$0 == objectUpload2.fileGroupUUID}
        guard filter1.count == 1, filter2.count == 1 else {
            XCTFail()
            return
        }
    }

    func testDeleteUndeclaredObjectFails() throws {
        try self.sync()
        
        do {
            try syncServer.markAsDeletedLocally(object: UUID())
        } catch let error {
            guard let error = error as? SyncServerError else {
                XCTFail()
                return
            }
            
            XCTAssert(.noObject == error)
        }
    }
    
    func testTwoObjectsNeedingDeletionMarkAsDeleted() throws {
        try self.sync()
        let sharingGroupUUID = try getSharingGroupUUID()
        
        let localFile = Self.exampleTextFileURL
        
        let (uploadObject1, example1) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        guard uploadObject1.uploads.count == 1,
            let uploadFile1 = uploadObject1.uploads.first else {
            XCTFail()
            return
        }
        
        let (uploadObject2, example2) = try uploadExampleTextFile(sharingGroupUUID: sharingGroupUUID, localFile: localFile)
        guard uploadObject2.uploads.count == 1,
            let uploadFile2 = uploadObject2.uploads.first else {
            XCTFail()
            return
        }

        try delete(object: uploadObject1.fileGroupUUID)
        try delete(object: uploadObject2.fileGroupUUID)

        // Reset the database show a state *as if* another client instance had done the upload/deleteion.
        database = try Connection(.inMemory)
        let fakeHelper = SignInServicesHelperFake(testUser: handlers.user)
        let fakeSignIns = SignIns(signInServicesHelper: fakeHelper)
        syncServer = try SyncServer(hashingManager: hashingManager, db: database, configuration: config, signIns: fakeSignIns)
        syncServer.delegate = self
        syncServer.credentialsDelegate = self
        syncServer.helperDelegate = self
        handlers.objectType = { _, _ in
            return nil
        }
        
        try syncServer.register(object: example1)
        try syncServer.register(object: example2)
        
        try sync(withSharingGroupUUID: sharingGroupUUID)
        
        // As synced both deletion flags will be set to true; need the local one set to false for test.
        guard let fileEntry1 = try DirectoryFileEntry.fetchSingleRow(db: database, where: DirectoryFileEntry.fileUUIDField.description == uploadFile1.uuid) else {
            XCTFail()
            return
        }
        
        guard let objectEntry1 = try DirectoryObjectEntry.fetchSingleRow(db: database, where: DirectoryObjectEntry.fileGroupUUIDField.description == uploadObject1.fileGroupUUID) else {
            XCTFail()
            return
        }
        
        try fileEntry1.update(setters:
            DirectoryFileEntry.deletedLocallyField.description <- false)
        try objectEntry1.update(setters:
            DirectoryObjectEntry.deletedLocallyField.description <- false)
            
        guard let fileEntry2 = try DirectoryFileEntry.fetchSingleRow(db: database, where: DirectoryFileEntry.fileUUIDField.description == uploadFile2.uuid) else {
            XCTFail()
            return
        }
        
        guard let objectEntry2 = try DirectoryObjectEntry.fetchSingleRow(db: database, where: DirectoryObjectEntry.fileGroupUUIDField.description == uploadObject2.fileGroupUUID) else {
            XCTFail()
            return
        }
        
        try fileEntry2.update(setters:
            DirectoryFileEntry.deletedLocallyField.description <- false)
        try objectEntry2.update(setters:
            DirectoryObjectEntry.deletedLocallyField.description <- false)
            
        let objectsToDelete = try syncServer.objectsNeedingLocalDeletion()
        guard objectsToDelete.count == 2 else {
            XCTFail()
            return
        }
        
        let filter1 = objectsToDelete.filter {$0 == uploadObject1.fileGroupUUID}
        let filter2 = objectsToDelete.filter {$0 == uploadObject2.fileGroupUUID}
        guard filter1.count == 1, filter2.count == 1 else {
            XCTFail()
            return
        }
        
        try syncServer.markAsDeletedLocally(object: uploadObject1.fileGroupUUID)
        
        let objectsToDelete2 = try syncServer.objectsNeedingLocalDeletion()
        guard objectsToDelete2.count == 1 else {
            XCTFail()
            return
        }
        
        XCTAssert(objectsToDelete2[0] == uploadObject2.fileGroupUUID)
        
        try syncServer.markAsDeletedLocally(object: uploadObject2.fileGroupUUID)
        
        let objectsToDelete3 = try syncServer.objectsNeedingLocalDeletion()
        guard objectsToDelete3.count == 0 else {
            XCTFail()
            return
        }
    }
}
