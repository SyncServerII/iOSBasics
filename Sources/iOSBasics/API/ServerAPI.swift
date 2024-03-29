import iOSSignIn
import ServerShared
import Foundation
import Version
import iOSShared
import SQLite

// Server requests are handled in two ways: file uploads and downloads-- on a background URL session. Other requests on a regular (non-background) URLSession.

class ServerAPI {
    enum ServerAPIError: Error {
        case nilStatusCode
        case non200StatusCode(Int)
        case couldNotCreateResponse
        case badCheckCreds
        case noUserInfoInCheckCreds
        case unknownServerError
        case couldNotCreateRequest
        case nilResponse
        case badAddUser
        case noExpectedResultKey
        case couldNotObtainHeaderParameters
        case couldNotGetCloudStorageType
        case resultURLObtainedWasNil
        case noURLObtained
        case couldNotComputeHash
        case networkingHashMismatch
        case badUploadIndex
        case badURLParameters
        case badUUID
        case socialAcceptanceNotAllowed
        case generic(String)
    }
    
    let networking: Networking
    let config: Configuration
    weak var delegate: ServerAPIDelegate!
    let hashingManager: HashingManager
    let serialQueue:DispatchQueue
    
    init?(database: Connection, hashingManager: HashingManager, delegate: ServerAPIDelegate, serialQueue:DispatchQueue, backgroundAsssertable: BackgroundAsssertable, config: Configuration) {
    
        guard let networking = Networking(database: database, serialQueue: serialQueue, backgroundAsssertable: backgroundAsssertable, delegate: delegate, config: config) else {
            return nil
        }
        
        self.networking = networking

        self.config = config
        self.delegate = delegate
        self.hashingManager = hashingManager
        self.serialQueue = serialQueue
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
    
    enum ServerResponse {
        case dictionary([AnyHashable:Any]?)
        case file(URL?)
        
        var contents: String? {
            switch self {
            case .dictionary(let dict):
                return "\(String(describing: dict))"
            case .file(let url):
                guard let url = url else {
                    return nil
                }
                
                guard let data = try? Data(contentsOf: url) else {
                    return nil
                }
                
                return String(data: data, encoding: .utf8)
            }
        }
    }
    
    func checkForError(statusCode:Int?, error:Error?, serverResponse:ServerResponse?) -> Error? {
        if statusCode == HTTPStatus.ok.rawValue || statusCode == nil  {
            return error
        }
        else {
            logger.error("checkForError: \(String(describing: error)); serverResponse: \(String(describing: serverResponse?.contents))")
            return ServerAPIError.non200StatusCode(statusCode!)
        }
    }
    
    // MARK: Health check

    func healthCheck(completion: @escaping (Swift.Result<HealthCheckResponse, Error>)->(Void)) {
        let endpoint = ServerEndpoints.healthCheck
        let serverURL = Self.makeURL(forEndpoint: endpoint, baseURL: config.baseURL)
        
        networking.sendRequestTo(serverURL, method: endpoint.method) { [weak self] response, httpStatus, error in
            guard let self = self else { return }
                
            if let resultError = self.checkForError(statusCode: httpStatus, error: error, serverResponse: .dictionary(response)) {
                completion(.failure(resultError))
            }
            else {
                if let response = response,
                    let healthCheckResponse = try? HealthCheckResponse.decode(response) {
                    completion(.success(healthCheckResponse))
                }
                else {
                    completion(.failure(ServerAPIError.couldNotCreateResponse))
                }
            }
        }
    }
    
    // MARK: Authentication/user-sign in
    
    enum AddUserResult {
        case userId(UserId)
        case userAlreadyExisted
    }
    
    // Adds the user specified by the creds property (or authenticationDelegate in ServerNetworking if that is nil).
    // If the type of owning user being added needs a cloud folder name, you must give it here (e.g., Google).
    func addUser(cloudFolderName: String? = nil, emailAddress: String? = nil, sharingGroupUUID: UUID, sharingGroupName: String?, completion: @escaping (Swift.Result<AddUserResult, Error>)->(Void)) {
    
        let endpoint = ServerEndpoints.addUser
                
        let addUserRequest = AddUserRequest()
        addUserRequest.sharingGroupName = sharingGroupName
        addUserRequest.cloudFolderName = cloudFolderName
        addUserRequest.sharingGroupUUID = sharingGroupUUID.uuidString
        addUserRequest.emailAddress = emailAddress
        
        guard addUserRequest.valid() else {
            completion(.failure(ServerAPIError.couldNotCreateRequest))
            return
        }
        
        guard let parameters = addUserRequest.urlParameters() else {
            completion(.failure(ServerAPIError.couldNotCreateRequest))
            return
        }

        let serverURL = Self.makeURL(forEndpoint: endpoint, baseURL: config.baseURL, parameters: parameters)
        
        networking.sendRequestTo(serverURL, method: endpoint.method) { response, httpStatus, error in
           
            guard let response = response else {
                completion(.failure(ServerAPIError.nilResponse))
                return
            }
            
            if let error = self.checkForError(statusCode: httpStatus, error: error, serverResponse: .dictionary(response)) {
                completion(.failure(error))
                return
            }
 
            guard let addUserResponse = try? AddUserResponse.decode(response) else {
                completion(.failure(ServerAPIError.badAddUser))
                return
            }
            
            if let userId = addUserResponse.userId {
                completion(.success(.userId(userId)))
            }
            else if let userAlreadyExisted = addUserResponse.userAlreadyExisted, userAlreadyExisted {
                completion(.success(.userAlreadyExisted))
            }
            else {
                completion(.failure(ServerAPIError.badAddUser))
            }
        }
    }
    
    enum CheckCredsResult {
        case noUser
        case user(userInfo:CheckCredsResponse.UserInfo, accessToken:String?)
    }
    
    // The credentials being checked are obtained from the `credentialsForNetworkRequests` delegate method.
    // The email address is just for migration purposes-- to get all users email addresses into the server db. It can be removed once we have them. See https://github.com/SyncServerII/ServerMain/issues/16
    func checkCreds(emailAddress: String? = nil, completion: @escaping (Swift.Result<CheckCredsResult, Error>)->(Void)) {
        let endpoint = ServerEndpoints.checkCreds
        
        let checkCredsRequest = CheckCredsRequest()
        checkCredsRequest.emailAddress = emailAddress

        guard checkCredsRequest.valid() else {
            completion(.failure(ServerAPIError.couldNotCreateRequest))
            return
        }

        let parameters = checkCredsRequest.urlParameters()
        let serverURL = Self.makeURL(forEndpoint: endpoint, baseURL: config.baseURL, parameters: parameters)
        
        networking.sendRequestTo(serverURL, method: endpoint.method) { response, httpStatus, error in

            if httpStatus == HTTPStatus.unauthorized.rawValue {
                logger.error("checkCreds: HTTPStatus.unauthorized")
                completion(.success(.noUser))
                return
            }

            guard let response = response else {
                completion(.failure(ServerAPIError.nilResponse))
                return
            }
            
            guard httpStatus == HTTPStatus.ok.rawValue else {
                if let errorResult = self.checkForError(statusCode: httpStatus, error: error, serverResponse: .dictionary(response)) {
                    completion(.failure(errorResult))
                }
                else {
                    completion(.failure(ServerAPIError.unknownServerError))
                }
                return
            }
            
            guard let checkCredsResponse = try? CheckCredsResponse.decode(response) else {
                completion(.failure(ServerAPIError.badCheckCreds))
                return
            }
            
            let accessToken = response[ServerConstants.httpResponseOAuth2AccessTokenKey] as? String
            
            guard let userInfo = checkCredsResponse.userInfo else {
                completion(.failure(ServerAPIError.noUserInfoInCheckCreds))
                return
            }
            
            completion(.success(.user(userInfo: userInfo, accessToken: accessToken)))
        }
    }
    
    func updateUser(userName: String, completion: @escaping (Error?)->(Void)) {
        let endpoint = ServerEndpoints.updateUser

        let updateUserRequest = UpdateUserRequest()
        updateUserRequest.userName = userName
        
        guard updateUserRequest.valid() else {
            completion(ServerAPIError.couldNotCreateRequest)
            return
        }
        
        guard let parameters = updateUserRequest.urlParameters() else {
            completion(ServerAPIError.couldNotCreateRequest)
            return
        }

        let serverURL = Self.makeURL(forEndpoint: endpoint, baseURL: config.baseURL, parameters: parameters)
        
        networking.sendRequestTo(serverURL, method: endpoint.method) { response, httpStatus, error in
        
            if let error = error {
                completion(error)
                return
            }
            
            guard let httpStatus = httpStatus else {
                completion(ServerAPIError.nilStatusCode)
                return
            }
        
            guard httpStatus == HTTPStatus.ok.rawValue else {
                completion(ServerAPIError.non200StatusCode(httpStatus))
                return
            }

            completion(nil)
        }
    }
    
    func removeUser(completion:@escaping (Error?)->(Void)) {
        let endpoint = ServerEndpoints.removeUser
        let serverURL = Self.makeURL(forEndpoint: endpoint, baseURL: config.baseURL)
        
        networking.sendRequestTo(serverURL, method: endpoint.method) { response,  httpStatus, error in
            completion(self.checkForError(statusCode: httpStatus, error: error, serverResponse: .dictionary(response)))
        }
    }
}
