//
//  File.swift
//  
//
//  Created by Christopher G Prince on 5/15/20.
//

import Foundation
import ServerShared
import iOSSignIn
import iOSShared
import Version

protocol ServerFile {
    var fileUUID:String {get}
    var fileVersion: FileVersionInt {get}
}

class Networking {
    weak var delegate: ServerAPIDelegate!
    let config: Configuration
    
    struct Configuration {
        let temporaryFileDirectory: URL
        let temporaryFilePrefix:String
        let temporaryFileExtension:String
        
        // Don't put a trailing slash on the baseURL
        let baseURL:String
        
        let minimumServerVersion: Version?
    }
    
    init(delegate: ServerAPIDelegate, config: Configuration) {
        self.delegate = delegate
        self.config = config
    }
    
    // Pass `credentials` if you need to replace the instance credentials.
    private func headerAuthentication(credentials: GenericCredentials? = nil) -> [String:String] {
        var result:[String:String]
        
        if let credentials = credentials {
            result = credentials.httpRequestHeaders
        }
        else {
            result = self.delegate.credentialsForNetworkRequests(self).httpRequestHeaders
        }
        
        result[ServerConstants.httpRequestDeviceUUID] = self.delegate.deviceUUID(self).uuidString
        return result
    }
    
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
    
    func uploadFile(file localFileURL: URL, to serverURL: URL, method: ServerHTTPMethod, completion: @escaping (HTTPURLResponse?, _ statusCode:Int?, Error?)->()) {
    
        // It appears that `session.uploadTask` has a problem with relative URL's. I get "NSURLErrorDomain Code=-1 "unknown error" if I pass one of these. Make sure the URL is not relative.
        let uploadFilePath = localFileURL.path
        let nonRelativeUploadURL = URL(fileURLWithPath: uploadFilePath)
        
        var request = URLRequest(url: serverURL)
        request.httpMethod = method.rawValue.uppercased()
        request.allHTTPHeaderFields = headerAuthentication()

        let sessionConfig = sessionConfiguration()
        
        sessionConfig.httpAdditionalHeaders = headerAuthentication()
        
        logger.info("httpAdditionalHeaders: \(String(describing: sessionConfig.httpAdditionalHeaders))")
        
        let session = URLSession(configuration: sessionConfig, delegate: nil, delegateQueue: nil)
        
        let task = session.uploadTask(with: request, fromFile: nonRelativeUploadURL) { data, urlResponse, error in
        
            if let error = error {
                completion(nil, nil, NetworkingError.uploadError(error))
                return
            }

            guard let response = urlResponse as? HTTPURLResponse else {
                completion(nil, nil, NetworkingError.noUploadResponse)
                return
            }
                        
            // Data, when converted to a string, is ""-- I'm not worrying about this for now, becase we're going to convert this over to a background task.

            completion(response, response.statusCode, nil)
        }
        
        task.resume()
    }
    
    func downloadFile(_ serverURL: URL, method: ServerHTTPMethod, completion: @escaping (_ downloadedFile: URL?, HTTPURLResponse?, _ statusCode:Int?, Error?)->()) {
    
        var request = URLRequest(url: serverURL)
        request.httpMethod = method.rawValue.uppercased()
        
        let sessionConfig = sessionConfiguration()
        
        sessionConfig.httpAdditionalHeaders = headerAuthentication()
        
        logger.info("httpAdditionalHeaders: \(String(describing: sessionConfig.httpAdditionalHeaders))")
        
        let session = URLSession(configuration: sessionConfig, delegate: nil, delegateQueue: nil)
        
        let task = session.downloadTask(with: request) { downloadURL, response, error in
            if let error = error {
                completion(nil, nil, nil, error)
                return
            }
            
            guard let response = response as? HTTPURLResponse else {
                completion(nil, nil, nil, NetworkingError.noDownloadResponse)
                return
            }
            
            guard let downloadURL = downloadURL else {
                completion(nil, nil, nil, NetworkingError.noDownloadURL)
                return
            }
                    
            var temporaryDirectory = self.config.temporaryFileDirectory
            var temporaryFile:URL!

            // Transfer the temporary file to a more permanent location. Have to do it right now. https://developer.apple.com/reference/foundation/urlsessiondownloaddelegate/1411575-urlsession
            do {
                try Files.createDirectoryIfNeeded(
                    self.config.temporaryFileDirectory)
                temporaryFile = try Files.createTemporary(withPrefix: self.config.temporaryFilePrefix, andExtension: self.config.temporaryFileExtension, inDirectory: &temporaryDirectory)
                _ = try FileManager.default.replaceItemAt(temporaryFile, withItemAt: downloadURL)
            }
            catch (let error) {
                logger.error("Could not move file: \(error)")
                completion(nil, nil, nil, error)
            }
            
            completion(temporaryFile, response, response.statusCode, nil)
        }
        
        task.resume()
    }
}
