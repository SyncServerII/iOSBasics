import XCTest
@testable import iOSBasics
import iOSSignIn
import ServerShared
import iOSShared
@testable import iOSDropbox
import SQLite

protocol ServerBasics {
}

extension ServerBasics {
    var cloudFolderName: String {
        return "CloudFolder"
    }
    
    // Don't put a trailing slash at end.
    static func baseURL() -> String {
        return "http://localhost:8080"
    }
}

protocol TestFiles {
}

extension TestFiles {
    static var exampleTextFile:String { return "Example.txt" }
    static var exampleImageFile:String { return "Cat.jpg" }

    static var exampleTextFileURL: URL {
        let directory = TestingFile.directoryOfFile(#file)
        return directory.appendingPathComponent(exampleTextFile)
    }
    
    var exampleTextFileURL: URL {
        return Self.exampleTextFileURL
    }
    
    static var exampleImageFileURL: URL {
        let directory = TestingFile.directoryOfFile(#file)
        return directory.appendingPathComponent(exampleImageFile)
    }

    var exampleImageFileURL: URL {
        return Self.exampleImageFileURL
    }
}

protocol APITests: ServerAPIDelegator {
    var api:ServerAPI! { get }
    var handlers: DelegateHandlers { get }
}
    
extension APITests where Self: XCTestCase {
    // Credentials/users
    
    func checkCreds() -> ServerAPI.CheckCredsResult? {
        let exp = expectation(description: "exp")
        var returnResult: ServerAPI.CheckCredsResult?
        
        api.checkCreds(handlers.user.credentials) { result in
            switch result {
            case .success(let result):
                returnResult = result
            case .failure:
                break
            }
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        return returnResult
    }
    
    // Files
    
    func getIndex(sharingGroupUUID: UUID?) -> ServerAPI.IndexResult? {
        let exp = expectation(description: "exp")
        
        var returnResult: ServerAPI.IndexResult?
        
        api.index(sharingGroupUUID: sharingGroupUUID) { result in
            switch result {
            case .failure:
                XCTFail()
            case .success(let result):
                returnResult = result
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        
        return returnResult
    }
    
    func uploadFile(file: ServerAPI.File, uploadIndex: Int32, uploadCount: Int32) -> Swift.Result<UploadFileResult, Error>? {
        var returnResult:Swift.Result<UploadFileResult, Error>?
        
        let exp = expectation(description: "exp")
        
        func uploadCompletedHandler(result: Swift.Result<UploadFileResult, Error>) {
            returnResult = result
            self.handlers.api.uploadCompletedHandler = nil
            exp.fulfill()
        }
        
        self.handlers.api.uploadCompletedHandler = uploadCompletedHandler

        let result = api.uploadFile(file: file, uploadIndex: uploadIndex, uploadCount: uploadCount)
        XCTAssert(result == nil)
        
        waitForExpectations(timeout: 10, handler: nil)
        
        return returnResult
    }
    
    func downloadFile(fileUUID: String, fileVersion: Int32, downloadObjectTrackerId: Int64, sharingGroupUUID: String) -> Swift.Result<DownloadFileResult, Error>? {
        
        var returnResult:Swift.Result<DownloadFileResult, Error>?
        let exp = expectation(description: "exp")

        func downloadCompletedHandler(result: Swift.Result<DownloadFileResult, Error>, file: Filenaming) {
            returnResult = result
            self.handlers.api.downloadCompletedHandler = nil
            exp.fulfill()
        }
        
        self.handlers.api.downloadCompletedHandler = downloadCompletedHandler

        let file = FileObject(fileUUID: fileUUID, fileVersion: fileVersion, trackerId: downloadObjectTrackerId)
        
        let result = api.downloadFile(file: file, sharingGroupUUID: sharingGroupUUID)
        XCTAssert(result == nil)
        
        waitForExpectations(timeout: 10, handler: nil)
        
        return returnResult
    }
    
    func getUploadsResults(deferredUploadId: Int64) -> Swift.Result<DeferredUploadStatus?, Error> {
        var theResult: Swift.Result<DeferredUploadStatus?, Error>!
        
        let exp = expectation(description: "exp")

        api.getUploadsResults(deferredUploadId: deferredUploadId) { result in
            logger.debug("getUploadsResults: \(result)")
            theResult = result
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        return theResult
    }
    
    func uploadDeletion(file: ServerAPI.DeletionFile, sharingGroupUUID: String) -> ServerAPI.DeletionFileResult? {
        let exp = expectation(description: "exp")
        var returnResult:ServerAPI.DeletionFileResult?
        
        api.uploadDeletion(file: file, sharingGroupUUID: sharingGroupUUID) { result in
            switch result {
            case .success(let result):
                returnResult = result
            case .failure:
                break
            }
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 20, handler: nil)

        return returnResult
    }
    
    func delayedGetUploadsResults(delay: TimeInterval = 10, deferredUploadId:Int64) -> DeferredUploadStatus? {
        // Wait for a bit, before polling server to see if the upload is done.
        let exp = expectation(description: "Deferred Upload")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            exp.fulfill()
        }
        waitForExpectations(timeout: delay + 2, handler: nil)
        
        var status: DeferredUploadStatus?
        let getUploadsResult = self.getUploadsResults(deferredUploadId: deferredUploadId)
        if case .success(let s) = getUploadsResult {
            status = s
        }
        
        return status
    }
    
    // Temporary until I get `sync` working again
    func getSharingGroup(createEntry: Bool = true, db: Connection) throws -> UUID {
        let sharingGroup = try getSharingGroupUUID()
        
        if createEntry {
            let entry = try SharingEntry(db: db, permission: Permission.admin, deleted: false, sharingGroupName: nil, sharingGroupUUID: sharingGroup, sharingGroupUsers: [], cloudStorageType: CloudStorageType.Dropbox)
            try entry.insert()
        }
        
        return sharingGroup
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
    
    func waitForUploadsToComplete(numberUploads: Int, gone: Bool = false, v0Upload: Bool = true) {
        var count = 0
        let exp = expectation(description: "exp")
        
        handlers.extras.uploadCompleted = { _, result in
            logger.info("waitForUploadsToComplete: uploadCompleted")
            count += 1
            
            switch result.uploadType {
            case .gone:
                guard gone else {
                    XCTFail()
                    exp.fulfill()
                    return
                }
                
            case .success:
                guard !gone else {
                    XCTFail()
                    exp.fulfill()
                    return
                }
            }
            
            if count == numberUploads {
                exp.fulfill()
            }
        }
        
        handlers.userEvent = { _, result in
            XCTFail("\(result)")
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        
        handlers.extras.uploadCompleted = nil
        handlers.userEvent = nil
    }
    
    func waitForDownloadsToComplete(numberExpected: UInt, expectedResult: URL? = nil) {
        var count:UInt = 0
        
        let exp = expectation(description: "exp")
        handlers.extras.downloadCompleted = { _, result in
            count += 1
            
            switch result.downloadType {
            case .gone:
                XCTFail()
                
            case .success(let url):
                if let expectedResult = expectedResult {
                    do {
                        let data1 = try Data(contentsOf: expectedResult)
                        let data2 = try Data(contentsOf: url)
                        XCTAssert(data1 == data2)
                    } catch {
                        XCTFail()
                    }
                }
                
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    XCTFail()
                }
            }
            
            if count >= numberExpected {
                exp.fulfill()
            }
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }

    // On success, returns the `deferredUploadId` for the file deletion. i.e., the deferred upload is still pending.
    func waitForDeletion(trackerId: Int64, file: ServerAPI.DeletionFile) -> Int64? {
        var deferredUploadId: Int64?
        
        let exp = expectation(description: "exp")
        
        handlers.api.backgroundRequestCompletedHandler = { result in
            switch result {
            case .failure:
                XCTFail()
                
            case .success(let successResult):
                switch successResult {
                case .gone:
                    XCTFail()
                    
                case .success(objectTrackerId: let id, let result):
                    XCTAssert(trackerId == id)
                    
                    guard let requestInfo = result.requestInfo else {
                        XCTFail()
                        return
                    }
                    
                    guard let info = try? JSONDecoder().decode(ServerAPI.DeletionRequestInfo.self, from: requestInfo) else {
                        XCTFail()
                        return
                    }

                    XCTAssert(info.uuid.uuidString == file.uuidString)
                    XCTAssert(info.uuidType == file.uuidType)
        
                    do {
                        let data = try Data(contentsOf: result.serverResponse)
                        let json = try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions(rawValue: UInt(0)))
                                
                        guard let jsonDict = json as? [String: Any] else {
                            XCTFail()
                            return
                        }
                                
                        let response = try UploadDeletionResponse.decode(jsonDict)
                        deferredUploadId = response.deferredUploadId
                    } catch let error {
                        XCTFail("\(error)")
                    }
                }
            }
            
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        
        return deferredUploadId
    }
}
