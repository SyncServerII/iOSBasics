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
import UIKit

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
    case versionError
    case invalidHTTPStatusCode
    case failover
}

protocol NetworkingDelegate: AnyObject {
    func badVersion(_ delegated: AnyObject, version: BadVersion)
    func networkingFailover(_ delegated: AnyObject, message: String)

    func credentialsForNetworkRequests(_ delegated: AnyObject) throws -> GenericCredentials
    func deviceUUID(_ delegated: AnyObject) -> UUID
    
    func uploadCompleted(_ delegated: AnyObject, file: Filenaming, result: Swift.Result<UploadFileResult, Error>)
    func downloadCompleted(_ delegated: AnyObject, file: Filenaming, result: Swift.Result<DownloadFileResult, Error>)
    func backgroundRequestCompleted(_ delegated: AnyObject, result: Swift.Result<BackgroundRequestResult, Error>)
}

// NSObject inheritance needed for URLSessionDelegate conformance.
class Networking: NSObject {
    weak var delegate: NetworkingDelegate!
    weak var transferDelegate: FileTransferDelegate!
    let config: Configuration
    var backgroundSession: URLSession!
    let backgroundCache: BackgroundCache
    var handleEventsForBackgroundURLSessionCompletionHandler: (() -> Void)?
    let serialQueue:DispatchQueue
    let backgroundAsssertable: BackgroundAsssertable

    init?(database:Connection, serialQueue:DispatchQueue, backgroundAsssertable: BackgroundAsssertable, delegate: NetworkingDelegate, transferDelegate:FileTransferDelegate? = nil, config: Configuration) {
        self.delegate = delegate
        self.transferDelegate = transferDelegate
        self.config = config
        self.backgroundCache = BackgroundCache(database: database)
        self.serialQueue = serialQueue
        self.backgroundAsssertable = backgroundAsssertable
        
        super.init()
        
        guard let session = createBackgroundURLSession() else {
            return nil
        }
        
        backgroundSession = session
    }
    
    /* "This method receives the session identifier you created in Listing 1 as its second parameter." (https://developer.apple.com/documentation/foundation/url_loading_system/downloading_files_in_the_background). I wonder what happens with app extensions?
     */
    func application(_ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void) {
        handleEventsForBackgroundURLSessionCompletionHandler = completionHandler
    }
    
    // An error occurred on the xpc connection to setup the background session: Error Domain=NSCocoaErrorDomain Code=4097 "connection to service on pid 0 named com.apple.nsurlsessiond" UserInfo={NSDebugDescription=connection to service on pid 0 named com.apple.nsurlsessiond}
    // https://forums.xamarin.com/discussion/170847/an-error-occurred-on-the-xpc-connection-to-setup-the-background-session
    // https://stackoverflow.com/questions/58212317/an-error-occurred-on-the-xpc-connection-to-setup-the-background-session
    // I'm working around this currently by not using a background URLSession when doing testing at the Package level.
    
    private func createBackgroundURLSession() -> URLSession? {
        let sessionConfiguration:URLSessionConfiguration
        // https://developer.apple.com/reference/foundation/urlsessionconfiguration/1407496-background
        if config.packageTests {
            sessionConfiguration = URLSessionConfiguration.default
        }
        else if let urlSessionBackgroundIdentifier = config.urlSessionBackgroundIdentifier {
            sessionConfiguration = URLSessionConfiguration.background(withIdentifier: urlSessionBackgroundIdentifier)
            sessionConfiguration.sessionSendsLaunchEvents = true
            sessionConfiguration.sharedContainerIdentifier = config.appGroupIdentifier
        }
        else {
            return nil
        }
        
        // See also https://stackoverflow.com/questions/23288780
        // https://developer.apple.com/forums/thread/101993
        // https://developer.apple.com/forums/thread/22690
        sessionConfiguration.timeoutIntervalForRequest = config.timeoutIntervalForRequest
        sessionConfiguration.timeoutIntervalForResource = config.timeoutIntervalForResource
        sessionConfiguration.waitsForConnectivity = true
        
        let urlSession = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: OperationQueue.main)
        return urlSession
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
        
        let uploadTask:URLSessionDataTask = session.dataTask(with: request) { [weak self] (data, urlResponse, error) in
            guard let self = self else { return }

            self.serialQueue.async { [weak self] in
                guard let self = self else { return }
                
                let (serverResponse, statusCode, error) = self.processResponse(data: data, urlResponse: urlResponse, error: error)
                completion?(serverResponse, statusCode, error)
            }
        }
        
        uploadTask.resume()
    }
    
    func validStatusCode(_ statusCode: Int?) -> Bool {
        if let statusCode = statusCode, statusCode >= 200, statusCode <= 299 {
            return true
        }
        else {
            return false
        }
    }

    private func processResponse(data:Data?, urlResponse:URLResponse?, error: Error?) -> (serverResponse:[String:Any]?, statusCode:Int?, error:Error?) {
    
        if let error = error {
            return (nil, nil, NetworkingError.urlSessionError(error))
        }
        
        // With an HTTP or HTTPS request, we get HTTPURLResponse back. See https://developer.apple.com/reference/foundation/urlsession/1407613-datatask
        guard let response = urlResponse as? HTTPURLResponse else {
            logger.error("processResponse: couldNotGetHTTPURLResponse")
            return (nil, nil, NetworkingError.couldNotGetHTTPURLResponse)
        }
        
        // Treating unauthorized specially because we attempt a credentials refresh in some cases when we get this.
        if response.statusCode == HTTPStatus.unauthorized.rawValue {
            return (nil, response.statusCode, nil)
        }

        if response.statusCode == HTTPStatus.serviceUnavailable.rawValue {
            logger.error("Failover due to HTTPStatus.serviceUnavailable")
            failover {
            }
            return (nil, response.statusCode, nil)
        }
        
        guard let data = data else {
            return (nil, response.statusCode, NetworkingError.couldNotGetData)
        }
        
        guard versionsAreOK(statusCode: response.statusCode, headerFields: response.allHeaderFields) else {
            logger.error("Versions not OK")
            return (nil, response.statusCode, NetworkingError.versionError)
        }
        
        var json:Any?
        do {
            try json = JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions(rawValue: UInt(0)))
        } catch (let error) {
            let stringFromData = String(data: data, encoding: .utf8)
            logger.error("processResponse: Error in JSON conversion: \(error); statusCode= \(response.statusCode); stringFromData: \(String(describing: stringFromData))")
            return (nil, response.statusCode, NetworkingError.jsonSerializationError(error))
        }
        
        guard let jsonDict = json as? [String: Any] else {
            return (nil, response.statusCode, NetworkingError.errorConvertingServerResponse)
        }
        
        var resultDict = jsonDict
        
        // Some responses (from endpoints doing sharing operations) have ServerConstants.httpResponseOAuth2AccessTokenKey in their header. Pass it up using the same key.
        if let accessTokenResponse = response.allHeaderFields[ServerConstants.httpResponseOAuth2AccessTokenKey] {
            resultDict[ServerConstants.httpResponseOAuth2AccessTokenKey] = accessTokenResponse
        }
        
        return (resultDict, response.statusCode, nil)
    }
    
    private func serverVersionTooLow(serverVersion: Version?, configMinimumServerVersion:Version?) -> Bool {
        guard let serverVersion = serverVersion,
            let configMinimumServerVersion = config.minimumServerVersion else {
            return false
        }
        
        return serverVersion < configMinimumServerVersion
    }
    
    private func serverVersionIsOK(statusCode: Int?, headerFields: [AnyHashable: Any]) -> Bool {
        var serverVersion:Version?
        if let version = headerFields[ServerConstants.httpResponseCurrentServerVersion] as? String {
            serverVersion = try? Version(version)
        }
        
        if config.minimumServerVersion == nil {
            // Client doesn't care which version of the server they are using.
            return true
        }
        // Only consider a serverVersion of nil to be valid if the statusCode was valid -- because I don't want the server being down to result in a bad server version response.
        else if (serverVersion == nil && validStatusCode(statusCode)) || serverVersionTooLow(serverVersion: serverVersion, configMinimumServerVersion:config.minimumServerVersion) {
        
            // Either: a) Client *does* care, but server isn't versioned, or
            // b) the actual server version is less than what the client needs.
            DispatchQueue.main.sync {
                self.delegate.badVersion(self, version: .badServerVersion(serverVersion))
            }
            return false
        }
        
        return true
    }
    
    private func clientAppVersionIsOK(headerFields: [AnyHashable: Any]) -> Bool {
        if let iosAppVersionRaw = headerFields[
            ServerConstants.httpResponseMinimumIOSClientAppVersion] as? String,
            let currentClientiOSAppVersion = config.currentClientAppVersion {
            
            let minimumIOSClientAppVersion: Version
            do {
                minimumIOSClientAppVersion = try Version(iosAppVersionRaw)
            } catch let error {
                logger.error("clientAppVersionIsOK: \(error)")
                return true
            }
            
            if currentClientiOSAppVersion < minimumIOSClientAppVersion {
                DispatchQueue.main.sync {
                    self.delegate.badVersion(self, version: .badClientAppVersion(minimumNeeded: minimumIOSClientAppVersion))
                }
                return false
            }
        }
        
        return true
    }
    
    func versionsAreOK(statusCode: Int?, headerFields: [AnyHashable: Any]) -> Bool {
        return serverVersionIsOK(statusCode: statusCode, headerFields: headerFields) &&
            clientAppVersionIsOK(headerFields: headerFields)
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
            logger.error("Networking.uploadCompleted: \(error)")
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
            delegate.downloadCompleted(self, file: file, result: .failure(error))
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

