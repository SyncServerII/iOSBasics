import iOSSignIn
import ServerShared
import Foundation
import Version
import iOSShared
import SQLite

// Requests are handled in two ways: file uploads and downloads-- on a background URL session. Other requests on a regular (non-background) URLSession.

class ServerAPI {
    enum ServerAPIError: Error {
        case non200StatusCode(Int)
        case couldNotCreateResponse
        case badCheckCreds
        case unknownServerError
        case couldNotCreateRequest
        case nilResponse
        case badAddUser
        case noExpectedResultKey
        case couldNotObtainHeaderParameters
        case couldNotGetCloudStorageType
        case resultURLObtainedWasNil
        case couldNotComputeHash
        case networkingHashMismatch
    }
    
    let networking: Networking
    let config: Networking.Configuration
    weak var delegate: ServerAPIDelegate!
    let hashingManager: HashingManager
    
    init(database: Connection, hashingManager: HashingManager, delegate: ServerAPIDelegate, config: Networking.Configuration) {
        self.networking = Networking(database: database, delegate: delegate, config: config)
        self.config = config
        self.delegate = delegate
        self.hashingManager = hashingManager
        self.networking.transferDelegate = self
    }
    
    enum CheckForExistingUserResult {
        case noUser
        case user(accessToken:String)
    }
    
    static func makeURL(forEndpoint endpoint:ServerEndpoint, baseURL: String, parameters:String? = nil) -> URL {
        var path = endpoint.pathWithSuffixSlash
        if let parameters = parameters {
            path += "?" + parameters
        }
        
        return URL(string: baseURL + path)!
    }
    
    func checkForError(statusCode:Int?, error:Error?) -> Error? {
        if statusCode == HTTPStatus.ok.rawValue || statusCode == nil  {
            return error
        }
        else {
            return ServerAPIError.non200StatusCode(statusCode!)
        }
    }
    
    // MARK: Health check

    func healthCheck(completion:((HealthCheckResponse?, Error?)->(Void))?) {
        let endpoint = ServerEndpoints.healthCheck
        let serverURL = Self.makeURL(forEndpoint: endpoint, baseURL: config.baseURL)
        
        networking.sendRequestTo(serverURL, method: endpoint.method) {
            response, httpStatus, error in
            
            let resultError = self.checkForError(statusCode: httpStatus, error: error)
            
            if resultError == nil {
                if let response = response,
                    let healthCheckResponse = try? HealthCheckResponse.decode(response) {
                    completion?(healthCheckResponse, nil)
                }
                else {
                    completion?(nil, ServerAPIError.couldNotCreateResponse)
                }
            }
            else {
                completion?(nil, resultError)
            }
        }
    }
    
    // MARK: Authentication/user-sign in
    
    // Adds the user specified by the creds property (or authenticationDelegate in ServerNetworking if that is nil).
    // If the type of owning user being added needs a cloud folder name, you must give it here (e.g., Google).
    func addUser(cloudFolderName: String? = nil, sharingGroupUUID: UUID, sharingGroupName: String?, completion:((UserId?, Error?)->(Void))?) {
    
        let endpoint = ServerEndpoints.addUser
                
        let addUserRequest = AddUserRequest()
        addUserRequest.sharingGroupName = sharingGroupName
        addUserRequest.cloudFolderName = cloudFolderName
        addUserRequest.sharingGroupUUID = sharingGroupUUID.uuidString
        
        guard addUserRequest.valid() else {
            completion?(nil, ServerAPIError.couldNotCreateRequest)
            return
        }
        
        guard let parameters = addUserRequest.urlParameters() else {
            completion?(nil, ServerAPIError.couldNotCreateRequest)
            return
        }

        let serverURL = Self.makeURL(forEndpoint: endpoint, baseURL: config.baseURL, parameters: parameters)
        
        networking.sendRequestTo(serverURL, method: endpoint.method) { response, httpStatus, error in
           
            guard let response = response else {
                completion?(nil, ServerAPIError.nilResponse)
                return
            }
            
            let error = self.checkForError(statusCode: httpStatus, error: error)

            guard error == nil else {
                completion?(nil, error)
                return
            }
            
            guard let checkCredsResponse = try? AddUserResponse.decode(response) else {
                completion?(nil, ServerAPIError.badAddUser)
                return
            }
            
            completion?(checkCredsResponse.userId, nil)
        }
    }
    
    enum CheckCredsResult {
        case noUser
        case user(UserId, accessToken:String?)
    }
    
    func checkCreds(_ creds: GenericCredentials, completion:((_ checkCredsResult:CheckCredsResult?, Error?)->(Void))?) {
        let endpoint = ServerEndpoints.checkCreds
        let serverURL = Self.makeURL(forEndpoint: endpoint, baseURL: config.baseURL)
        
        networking.sendRequestTo(serverURL, method: endpoint.method) { response, httpStatus, error in
        
            var result:CheckCredsResult?

            if httpStatus == HTTPStatus.unauthorized.rawValue {
                result = .noUser
            }
            else if httpStatus == HTTPStatus.ok.rawValue {
                guard let checkCredsResponse = try? CheckCredsResponse.decode(response!) else {
                    completion?(nil, ServerAPIError.badCheckCreds)
                    return
                }
                
                let accessToken = response?[ServerConstants.httpResponseOAuth2AccessTokenKey] as? String
                result = .user(checkCredsResponse.userId, accessToken: accessToken)
            }
            
            if result == nil {
                if let errorResult = self.checkForError(statusCode: httpStatus, error: error) {
                    completion?(nil, errorResult)
                }
                else {
                    completion?(nil, ServerAPIError.unknownServerError)
                }
            }
            else {
                completion?(result, nil)
            }
        }
    }
    
    func removeUser(retryIfError:Bool=true, completion:((Error?)->(Void))?) {
        let endpoint = ServerEndpoints.removeUser
        let serverURL = Self.makeURL(forEndpoint: endpoint, baseURL: config.baseURL)
        
        networking.sendRequestTo(serverURL, method: endpoint.method) { response,  httpStatus, error in
            completion?(self.checkForError(statusCode: httpStatus, error: error))
        }
    }
    
    func redeemSharingInvitation(sharingInvitationUUID:String, cloudFolderName: String?, completion:((_ accessToken:String?, _ sharingGroupUUID: String?, Error?)->(Void))?) {
    }
    
    // MARK: Files
    
    struct IndexResult {
        // This is nil if there are no files.
        let fileIndex: [FileInfo]?
        
        let masterVersion: MasterVersionInt?
        let sharingGroups:[SharingGroup]
    }
    
    func index(sharingGroupUUID: UUID?, completion:((Swift.Result<IndexResult, Error>)->())?) {
        let endpoint = ServerEndpoints.index
        
        let indexRequest = IndexRequest()
        indexRequest.sharingGroupUUID = sharingGroupUUID?.uuidString
        
        guard indexRequest.valid() else {
            completion?(.failure(ServerAPIError.couldNotCreateRequest))
            return
        }

        let urlParameters = indexRequest.urlParameters()
        let serverURL = Self.makeURL(forEndpoint: endpoint, baseURL: config.baseURL, parameters: urlParameters)
        
        networking.sendRequestTo(serverURL, method: endpoint.method) { response,  httpStatus, error in
            let resultError = self.checkForError(statusCode: httpStatus, error: error)
            
            if let resultError = resultError {
                completion?(.failure(resultError))
            }
            else if let response = response,
                let indexResponse = try? IndexResponse.decode(response) {
                let result = IndexResult(fileIndex: indexResponse.fileIndex, masterVersion: indexResponse.masterVersion, sharingGroups: indexResponse.sharingGroups)
                completion?(.success(result))
            }
            else {
                completion?(.failure(ServerAPIError.couldNotCreateResponse))
            }
        }
    }
}
