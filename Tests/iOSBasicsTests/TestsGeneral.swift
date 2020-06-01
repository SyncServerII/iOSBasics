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
    
protocol APITests: ServerAPIDelegate {
    var deviceUUID:UUID { get }
    var credentials: GenericCredentials! { get set }
    var hashingManager: HashingManager { get }
    var api:ServerAPI! { get }
    
    var uploadCompletedHandler: ((_ result: Swift.Result<UploadFileResult, Error>) -> ())? {set get}
    var downloadCompletedHandler: ((_ result: Swift.Result<DownloadFileResult, Error>) -> ())? {set get}
}

extension APITests where Self: XCTestCase {
    var exampleTextFile:String { return "Example.txt" }

    // Dropbox
    
    @discardableResult
    func addDropboxUser() -> Bool {
        let exp = expectation(description: "exp")
        
        var success = true
        let uuid = UUID()
        
        api.addUser(cloudFolderName: nil, sharingGroupUUID: uuid, sharingGroupName: nil) { userId, error in
            success = userId != nil && error == nil
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
        
        api.checkCreds(credentials) { result, error in
            if error == nil {
                returnResult = result
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
    
    func uploadFile(file: ServerAPI.File, masterVersion:MasterVersionInt) -> Swift.Result<UploadFileResult, Error>? {
        var returnResult:Swift.Result<UploadFileResult, Error>?
        
        let exp = expectation(description: "exp")
        
        func uploadCompletedHandler(result: Swift.Result<UploadFileResult, Error>) {
            returnResult = result
            self.uploadCompletedHandler = nil
            exp.fulfill()
        }
        
        self.uploadCompletedHandler = uploadCompletedHandler

        let result = api.uploadFile(file: file, serverMasterVersion: masterVersion)
        XCTAssert(result == nil)
        
        waitForExpectations(timeout: 10, handler: nil)
        
        return returnResult
    }
    
    func commitUploads(masterVersion: MasterVersionInt, sharingGroupUUID: UUID, options: ServerAPI.CommitUploadsOptions? = nil) -> ServerAPI.CommitUploadsResult? {
        var returnResult:ServerAPI.CommitUploadsResult?
        
        let exp = expectation(description: "exp")

        api.commitUploads(serverMasterVersion: masterVersion, sharingGroupUUID: sharingGroupUUID, options: options) { result, error in
            if error == nil {
                returnResult = result
            }
            exp.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
        
        return returnResult
    }
    
    func downloadFile(fileUUID: String, fileVersion: Int32, serverMasterVersion: MasterVersionInt, sharingGroupUUID: String, appMetaDataVersion: AppMetaDataVersionInt?) -> Swift.Result<DownloadFileResult, Error>? {
        
        var returnResult:Swift.Result<DownloadFileResult, Error>?
        let exp = expectation(description: "exp")

        func downloadCompletedHandler(result: Swift.Result<DownloadFileResult, Error>) {
            returnResult = result
            self.downloadCompletedHandler = nil
            exp.fulfill()
        }
        
        self.downloadCompletedHandler = downloadCompletedHandler

        let file = FilenamingWithAppMetaDataVersion(fileUUID: fileUUID, fileVersion: fileVersion, appMetaDataVersion: appMetaDataVersion)
        
        let result = api.downloadFile(file: file, serverMasterVersion: serverMasterVersion, sharingGroupUUID: sharingGroupUUID)
        XCTAssert(result == nil)
        
        waitForExpectations(timeout: 10, handler: nil)
        
        return returnResult
    }
}

extension APITests /* : ServerAPIDelegate */ {
    func credentialsForNetworkRequests(_ api: AnyObject) -> GenericCredentials {
        return credentials
    }
    
    func deviceUUID(_ api: AnyObject) -> UUID {
        return deviceUUID
    }
    
    func hasher(_ api: AnyObject, forCloudStorageType cloudStorageType: CloudStorageType) throws -> CloudStorageHashing {
        return try hashingManager.hashFor(cloudStorageType: cloudStorageType)
    }
    
    func uploadCompleted(_ api: AnyObject, result: Swift.Result<UploadFileResult, Error>) {
        uploadCompletedHandler?(result)
    }
    
    func downloadCompleted(_ api: AnyObject, result: Swift.Result<DownloadFileResult, Error>) {
        downloadCompletedHandler?(result)
    }
}
