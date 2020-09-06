import XCTest
@testable import iOSBasics
import iOSSignIn
import ServerShared
import iOSShared
@testable import iOSDropbox

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
    var exampleTextFile:String { return "Example.txt" }
    var exampleImageFile:String { return "Cat.jpg" }

    var exampleTextFileURL: URL {
        let directory = TestingFile.directoryOfFile(#file)
        return directory.appendingPathComponent(exampleTextFile)
    }
    
    var exampleImageFileURL: URL {
        let directory = TestingFile.directoryOfFile(#file)
        return directory.appendingPathComponent(exampleImageFile)
    }
}

protocol APITests: ServerAPIDelegator {
    var api:ServerAPI! { get }
}

extension APITests where Self: XCTestCase {
    // Credentials/users
    
    func checkCreds() -> ServerAPI.CheckCredsResult? {
        let exp = expectation(description: "exp")
        var returnResult: ServerAPI.CheckCredsResult?
        
        api.checkCreds(user.credentials) { result in
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
            self.uploadCompletedHandler = nil
            exp.fulfill()
        }
        
        self.uploadCompletedHandler = uploadCompletedHandler

        let result = api.uploadFile(file: file, uploadIndex: uploadIndex, uploadCount: uploadCount)
        XCTAssert(result == nil)
        
        waitForExpectations(timeout: 10, handler: nil)
        
        return returnResult
    }
    
    func downloadFile(fileUUID: String, fileVersion: Int32, downloadObjectTrackerId: Int64, sharingGroupUUID: String) -> Swift.Result<DownloadFileResult, Error>? {
        
        var returnResult:Swift.Result<DownloadFileResult, Error>?
        let exp = expectation(description: "exp")

        func downloadCompletedHandler(result: Swift.Result<DownloadFileResult, Error>) {
            returnResult = result
            self.downloadCompletedHandler = nil
            exp.fulfill()
        }
        
        self.downloadCompletedHandler = downloadCompletedHandler

        let file = FileObject(fileUUID: fileUUID, fileVersion: fileVersion, trackerId: downloadObjectTrackerId)
        
        let result = api.downloadFile(file: file, downloadObjectTrackerId: downloadObjectTrackerId, sharingGroupUUID: sharingGroupUUID)
        XCTAssert(result == nil)
        
        waitForExpectations(timeout: 10, handler: nil)
        
        return returnResult
    }
    
    func getUploadsResults(deferredUploadId: Int64) -> Result<DeferredUploadStatus?, Error> {
        var theResult: Result<DeferredUploadStatus?, Error>!
        
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
        
        waitForExpectations(timeout: 10, handler: nil)

        return returnResult
    }
    
    func delayedGetUploadsResults(delay: TimeInterval = 8, deferredUploadId:Int64) -> DeferredUploadStatus? {
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
}
