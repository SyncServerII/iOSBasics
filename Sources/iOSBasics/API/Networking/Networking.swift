//
//  Networking.swift
//  
//
//  Created by Christopher G Prince on 5/15/20.
//

import Foundation
import ServerShared
import iOSSignIn
import iOSShared
import Version
import SQLite

enum NetworkingError: Error {
    case couldNotGetHTTPURLResponse
    case jsonSerializationError(Error)
    case errorConvertingServerResponse
    case urlSessionError(Error?)
    case couldNotGetData
    case uploadError(Error)
    case noUploadResponse
    case noDownloadResponse
    case noDownloadURL
    case unexpectedTransferType
    case moreThanOneNetworkCache
    case couldNotGetCache
}

protocol NetworkingDelegate: AnyObject {
    func credentialsForNetworkRequests(_ delegated: AnyObject) throws -> GenericCredentials
    func deviceUUID(_ delegated: AnyObject) -> UUID
    
    func uploadCompleted(_ delegated: AnyObject, file: Filenaming, result: Swift.Result<UploadFileResult, Error>)
    func downloadCompleted(_ delegated: AnyObject, result: Swift.Result<DownloadFileResult, Error>)
    func backgroundRequestCompleted(_ delegated: AnyObject, result: Swift.Result<BackgroundRequestResult, Error>)
}

// NSObject inheritance needed for URLSessionDelegate conformance.
class Networking: NSObject {
    weak var delegate: NetworkingDelegate!
    weak var transferDelegate: FileTransferDelegate!
    let config: Configuration
    var backgroundSession: URLSession!
    let backgroundCache: BackgroundCache
    
    init(database:Connection, delegate: NetworkingDelegate, transferDelegate:FileTransferDelegate? = nil, config: Configuration) {
        self.delegate = delegate
        self.transferDelegate = transferDelegate
        self.config = config
        self.backgroundCache = BackgroundCache(database: database)
        super.init()
        backgroundSession = createBackgroundURLSession()
    }
    
    // An error occurred on the xpc connection to setup the background session: Error Domain=NSCocoaErrorDomain Code=4097 "connection to service on pid 0 named com.apple.nsurlsessiond" UserInfo={NSDebugDescription=connection to service on pid 0 named com.apple.nsurlsessiond}
    // https://forums.xamarin.com/discussion/170847/an-error-occurred-on-the-xpc-connection-to-setup-the-background-session
    // https://stackoverflow.com/questions/58212317/an-error-occurred-on-the-xpc-connection-to-setup-the-background-session
    // I'm working around this currently by not using a background URLSession when doing testing at the Package level.
    
    private func createBackgroundURLSession() -> URLSession {
        let appBundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as! String
        
        let sessionConfiguration:URLSessionConfiguration
        // https://developer.apple.com/reference/foundation/urlsessionconfiguration/1407496-background
        if config.packageTests {
            sessionConfiguration = URLSessionConfiguration.default
        }
        else {
            sessionConfiguration = URLSessionConfiguration.background(withIdentifier: "biz.SpasticMuffin.SyncServer." + appBundleName)
        }
        
        sessionConfiguration.timeoutIntervalForRequest = 60
        
        return URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: OperationQueue.main)
    }
    
    // Pass `credentials` if you need to replace the instance credentials.
    private func headerAuthentication(credentials: GenericCredentials? = nil) -> [String:String] {
        var result = [String:String]()
        
        if let credentials = credentials {
            result = credentials.httpRequestHeaders
        }
        else {
            do {
                result = try self.delegate.credentialsForNetworkRequests(self).httpRequestHeaders
            } catch let error {
                logger.error("\(error)")
            }
        }
        
        result[ServerConstants.httpRequestDeviceUUID] = self.delegate.deviceUUID(self).uuidString
        return result
    }

    struct RequestConfiguration {
        static let defaultTimeout:TimeInterval = 60

        let dataToUpload:Data?
        let timeoutIntervalForRequest:TimeInterval
        let credentials:GenericCredentials?
        
        init(dataToUpload:Data? = nil, timeoutIntervalForRequest:TimeInterval = defaultTimeout, credentials:GenericCredentials? = nil) {
            self.dataToUpload = dataToUpload
            self.timeoutIntervalForRequest = timeoutIntervalForRequest
            self.credentials = credentials
        }
    }
    
    func sessionConfiguration(configuration: RequestConfiguration? = nil) -> URLSessionConfiguration {
        let sessionConfiguration = URLSessionConfiguration.default
        // This really seems to be the critical timeout parameter for my usage. See also https://github.com/Alamofire/Alamofire/issues/1266 and https://stackoverflow.com/questions/19688175/nsurlsessionconfiguration-timeoutintervalforrequest-vs-nsurlsession-timeoutinter
        sessionConfiguration.timeoutIntervalForRequest = configuration?.timeoutIntervalForRequest ?? RequestConfiguration.defaultTimeout

        sessionConfiguration.timeoutIntervalForResource = configuration?.timeoutIntervalForRequest ?? RequestConfiguration.defaultTimeout

        // https://useyourloaf.com/blog/urlsession-waiting-for-connectivity/
        sessionConfiguration.waitsForConnectivity = true
        
        return sessionConfiguration
    }
    
    func sendRequestTo(_ serverURL: URL, method: ServerHTTPMethod, configuration: RequestConfiguration? = nil, completion:((_ serverResponse:[String:Any]?, _ statusCode:Int?, _ error:Error?)->())?) {
    
        let sessionConfig = sessionConfiguration(configuration: configuration)
        
        sessionConfig.httpAdditionalHeaders = headerAuthentication(credentials: configuration?.credentials)
        
        logger.info("httpAdditionalHeaders: \(String(describing: sessionConfig.httpAdditionalHeaders))")
        
        let session = URLSession(configuration: sessionConfig, delegate: nil, delegateQueue: nil)
        
        // Data uploading task. We could use NSURLSessionUploadTask instead of NSURLSessionDataTask if we needed to support uploads in the background
        
        var request = URLRequest(url: serverURL)
        request.httpMethod = method.rawValue.uppercased()
        request.httpBody = configuration?.dataToUpload
        
        logger.info("sendRequestTo: serverURL: \(serverURL)")
        
        let uploadTask:URLSessionDataTask = session.dataTask(with: request) { (data, urlResponse, error) in
            self.processResponse(data: data, urlResponse: urlResponse, error: error, completion: completion)
        }
        
        uploadTask.resume()
    }

    private func processResponse(data:Data?, urlResponse:URLResponse?, error: Error?, completion:((_ serverResponse:[String:Any]?, _ statusCode:Int?, _ error:Error?)->())?) {
        if error == nil {
            // With an HTTP or HTTPS request, we get HTTPURLResponse back. See https://developer.apple.com/reference/foundation/urlsession/1407613-datatask
            guard let response = urlResponse as? HTTPURLResponse else {
                completion?(nil, nil, NetworkingError.couldNotGetHTTPURLResponse)
                return
            }
            
            // Treating unauthorized specially because we attempt a credentials refresh in some cases when we get this.
            if response.statusCode == HTTPStatus.unauthorized.rawValue {
                completion?(nil, response.statusCode, nil)
                return
            }
            
            if response.statusCode == HTTPStatus.serviceUnavailable.rawValue {
                completion?(nil, response.statusCode, nil)
                return
            }
            
            if serverVersionIsOK(headerFields: response.allHeaderFields) {
                var json:Any?
                do {
                    try json = JSONSerialization.jsonObject(with: data!, options: JSONSerialization.ReadingOptions(rawValue: UInt(0)))
                } catch (let error) {
                    logger.error("processResponse: Error in JSON conversion: \(error); statusCode= \(response.statusCode)")
                    completion?(nil, response.statusCode, NetworkingError.jsonSerializationError(error))
                    return
                }
                
                guard let jsonDict = json as? [String: Any] else {
                    completion?(nil, response.statusCode, NetworkingError.errorConvertingServerResponse)
                    return
                }
                
                var resultDict = jsonDict
                
                // Some responses (from endpoints doing sharing operations) have ServerConstants.httpResponseOAuth2AccessTokenKey in their header. Pass it up using the same key.
                if let accessTokenResponse = response.allHeaderFields[ServerConstants.httpResponseOAuth2AccessTokenKey] {
                    resultDict[ServerConstants.httpResponseOAuth2AccessTokenKey] = accessTokenResponse
                }
                
                completion?(resultDict, response.statusCode, nil)
            }
        }
        else {
            completion?(nil, nil, NetworkingError.urlSessionError(error))
        }
    }
    
    private func serverVersionIsOK(headerFields: [AnyHashable: Any]) -> Bool {
        var serverVersion:Version?
        if let version = headerFields[ServerConstants.httpResponseCurrentServerVersion] as? String {
            serverVersion = try? Version(version)
        }
        
        if config.minimumServerVersion == nil {
            // Client doesn't care which version of the server they are using.
            return true
        }
        else if serverVersion == nil || serverVersion! < config.minimumServerVersion! {
            // Either: a) Client *does* care, but server isn't versioned, or
            // b) the actual server version is less than what the client needs.
            DispatchQueue.main.sync {
                //self.syncServerDelegate?.syncServerErrorOccurred(error:
                //    .badServerVersion(actualServerVersion: serverVersion))
            }
            return false
        }
        
        return true
    }
    
    private func uploadFile(localURL: URL, to serverURL: URL, method: ServerHTTPMethod) -> URLSessionUploadTask {

        var request = URLRequest(url: serverURL)
        request.httpMethod = method.rawValue.uppercased()
        request.allHTTPHeaderFields = headerAuthentication()
        
        // It appears that `session.uploadTask` has a problem with relative URL's. I get "NSURLErrorDomain Code=-1 "unknown error" if I pass one of these. Make sure the URL is not relative.
        let uploadFilePath = localURL.path
        let nonRelativeUploadURL = URL(fileURLWithPath: uploadFilePath)
        return backgroundSession.uploadTask(with: request, fromFile: nonRelativeUploadURL)
    }
    
    // The return value just indicates if the upload could be started, not whether the upload completed. The transferDelegate is used for further indications if the return result is nil.
    func upload(fileUUID:String, uploadObjectTrackerId: Int64, from localURL: URL, toServerURL serverURL: URL, method: ServerHTTPMethod) -> Error? {
        let task = uploadFile(localURL: localURL, to: serverURL, method: method)

        do {
            try backgroundCache.initializeUploadCache(fileUUID: fileUUID, uploadObjectTrackerId: uploadObjectTrackerId, taskIdentifer: task.taskIdentifier)
        } catch let error {
            task.cancel()
            let file = FileObject(fileUUID: fileUUID, fileVersion: nil, trackerId: uploadObjectTrackerId)
            delegate.uploadCompleted(self, file: file, result: .failure(error))
            return error
        }

        task.resume()
        return nil
    }
    
    private func downloadFrom(_ serverURL: URL, method: ServerHTTPMethod) -> URLSessionDownloadTask {
    
        var request = URLRequest(url: serverURL)
        request.httpMethod = method.rawValue.uppercased()
        request.allHTTPHeaderFields = headerAuthentication()
                
        return backgroundSession.downloadTask(with: request)
    }
    
    func download(file:Filenaming, downloadObjectTrackerId: Int64, fromServerURL serverURL: URL, method: ServerHTTPMethod) -> Error? {
    
        let task = downloadFrom(serverURL, method: method)
        
        do {
            try backgroundCache.initializeDownloadCache(file: file, taskIdentifer: task.taskIdentifier)
        } catch let error {
            task.cancel()
            delegate.downloadCompleted(self, result: .failure(error))
            return error
        }

        task.resume()
        return nil
    }
    
    // userInfo is for request specific info.
    func sendBackgroundRequestTo(_ serverURL: URL, method: ServerHTTPMethod, uuid: UUID, trackerId: Int64, requestInfo: Data? = nil) -> Error? {

        let task = downloadFrom(serverURL, method: method)

        do {
            try backgroundCache.initializeRequestCache(uuid: uuid.uuidString, trackerId: trackerId, taskIdentifer: task.taskIdentifier, requestInfo: requestInfo)
        } catch let error {
            task.cancel()
            delegate.backgroundRequestCompleted(self, result: .failure(error))
            return error
        }

        task.resume()
        return nil
    }
}

