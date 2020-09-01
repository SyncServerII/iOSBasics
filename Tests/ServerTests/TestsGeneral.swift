import XCTest
@testable import iOSBasics
import iOSSignIn
import ServerShared
import iOSShared
@testable import iOSDropbox

protocol ServerBasics {
}

extension ServerBasics {
    // Don't put a trailing slash at end.
    static func baseURL() -> String {
        return "http://localhost:8080"
    }
}

protocol Dropbox {
}

extension Dropbox {
    func createDropboxCredentials() throws -> DropboxCredentials {
        let savedCredentials = try loadDropboxCredentials()
        return DropboxCredentials(savedCreds:savedCredentials)
    }
    
    func loadDropboxCredentials() throws -> DropboxSavedCreds {
        let dropboxCredentialsFile = "Dropbox.credentials"
        let thisDirectory = TestingFile.directoryOfFile(#file)
        let dropboxCredentials = thisDirectory.appendingPathComponent(dropboxCredentialsFile)
        return try DropboxSavedCreds.fromJSON(file: dropboxCredentials)
    }
    
    func setupDropboxCredentials() throws -> DropboxCredentials {
        let savedCredentials = try loadDropboxCredentials()
        return DropboxCredentials(savedCreds:savedCredentials)
    }
}
    
protocol APITests: ServerAPIDelegate, NetworkingProtocol {
    var deviceUUID:UUID { get }
    var api:ServerAPI! { get }
}

extension APITests where Self: XCTestCase {
    var exampleTextFile:String { return "Example.txt" }

    // Dropbox
    
    @discardableResult
    func addDropboxUser() -> Bool {
        let exp = expectation(description: "exp")
        
        var success = true
        let uuid = UUID()
        
        api.addUser(cloudFolderName: nil, sharingGroupUUID: uuid, sharingGroupName: nil) { result in
            switch result {
            case .success:
                break
            case .failure:
                success = false
            }
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        
        return success
    }

    @discardableResult
    func removeDropboxUser() -> Bool {
        let exp = expectation(description: "exp")
        
        var success = true
        
        api.removeUser { error in
            success = error == nil
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        
        return success
    }
    
    // Credentials/users
    
    func checkCreds() -> ServerAPI.CheckCredsResult? {
        let exp = expectation(description: "exp")
        var returnResult: ServerAPI.CheckCredsResult?
        
        api.checkCreds(credentials) { result in
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
    
    func downloadFile(fileUUID: String, fileVersion: Int32, sharingGroupUUID: String) -> Swift.Result<DownloadFileResult, Error>? {
        
        var returnResult:Swift.Result<DownloadFileResult, Error>?
        let exp = expectation(description: "exp")

        func downloadCompletedHandler(result: Swift.Result<DownloadFileResult, Error>) {
            returnResult = result
            self.downloadCompletedHandler = nil
            exp.fulfill()
        }
        
        self.downloadCompletedHandler = downloadCompletedHandler

        let file = FileObject(fileUUID: fileUUID, fileVersion: fileVersion)
        
        let result = api.downloadFile(file: file, sharingGroupUUID: sharingGroupUUID)
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
}
