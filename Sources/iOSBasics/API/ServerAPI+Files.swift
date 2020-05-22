import ServerShared
import Foundation
import iOSShared

extension ServerAPI {
    struct File : Filenaming {
        let localURL:URL
        let fileUUID:String!
        let fileGroupUUID:String?
        let sharingGroupUUID: String
        let mimeType:MimeType
        let deviceUUID:String
        let appMetaData:AppMetaData?
        let fileVersion:FileVersionInt!
        let checkSum:String
    }
    
    enum UploadFileResult {
        case success(creationDate: Date, updateDate: Date)
        case serverMasterVersionUpdate(Int64)
        
        // The GoneReason should never be fileRemovedOrRenamed-- because a new upload would upload the next version, not accessing the current version.
        case gone(GoneReason)
    }
    
    // Set undelete = true in order to do an upload undeletion. The server file must already have been deleted. The meaning is to upload a new file version for a file that has already been deleted on the server. The use case is for conflict resolution-- when a download deletion and a file upload are taking place at the same time, and the client want's its upload to take priority over the download deletion.
    func uploadFile(file:File, serverMasterVersion:MasterVersionInt, undelete:Bool = false, completion:((UploadFileResult?, Error?)->(Void))?) {
        let endpoint = ServerEndpoints.uploadFile

        logger.info("file.fileUUID: \(String(describing: file.fileUUID))")

        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = file.fileUUID
        uploadRequest.mimeType = file.mimeType.rawValue
        uploadRequest.fileVersion = file.fileVersion
        uploadRequest.masterVersion = serverMasterVersion
        uploadRequest.sharingGroupUUID = file.sharingGroupUUID
        uploadRequest.checkSum = file.checkSum
        
        if file.fileVersion == 0 {
            uploadRequest.fileGroupUUID = file.fileGroupUUID
        }
        
        if undelete {
            uploadRequest.undeleteServerFile = true
        }
        
        guard uploadRequest.valid() else {
            completion?(nil, ServerAPIError.couldNotCreateRequest)
            return
        }
        
        uploadRequest.appMetaData = file.appMetaData
        
        assert(endpoint.method == .post)
        
        let parameters = uploadRequest.urlParameters()!
        let serverURL = Self.makeURL(forEndpoint: endpoint, baseURL: config.baseURL, parameters: parameters)

        networking.uploadFile(file: file.localURL, to: serverURL, method: endpoint.method) { response, httpStatus, error in

            /*
            if httpStatus == HTTPStatus.gone.rawValue,
                let goneReasonRaw = uploadResponseBody?[GoneReason.goneReasonKey] as? String,
                let goneReason = GoneReason(rawValue: goneReasonRaw) {
                completion?(UploadFileResult.gone(goneReason), nil)
                return
            }
            */
            
            let resultError = self.checkForError(statusCode: httpStatus, error: error)

            if resultError == nil {
                logger.info("response?.allHeaderFields: \(String(describing: response?.allHeaderFields))")
                if let parms = response?.allHeaderFields[ServerConstants.httpResponseMessageParams] as? String,
                    let jsonDict = self.toJSONDictionary(jsonString: parms) {
                    logger.info("jsonDict: \(jsonDict)")
                    
                    guard let uploadFileResponse = try? UploadFileResponse.decode(jsonDict) else {
                        completion?(nil, ServerAPIError.couldNotCreateResponse)
                        return
                    }
                    
                    if let versionUpdate = uploadFileResponse.masterVersionUpdate {
                        let message = UploadFileResult.serverMasterVersionUpdate(versionUpdate)
                        logger.info("\(message)")
                        completion?(message, nil)
                        return
                    }
                    
                    guard let creationDate = uploadFileResponse.creationDate, let updateDate = uploadFileResponse.updateDate else {
                        completion?(nil, ServerAPIError.noExpectedResultKey)
                        return
                    }
                    
                    completion?(UploadFileResult.success(creationDate: creationDate, updateDate: updateDate), nil)
                }
                else {
                    completion?(nil, ServerAPIError.couldNotObtainHeaderParameters)
                }
            }
            else {
                completion?(nil, resultError)
            }
        }
    }
    
    enum CommitUploadsResult {
        case success(numberUploadsTransferred:Int64)
        case serverMasterVersionUpdate(Int64)
    }
    
    struct CommitUploadsOptions {
        // I'm providing a numberOfDeletions parameter here because the duration of these requests varies, if we're doing deletions, based on the number of items we're deleting.
        let numberOfDeletions:UInt
        
        let sharingGroupNameUpdate: String?
        let pushNotificationMessage: String?
        
        init(numberOfDeletions:UInt = 0, sharingGroupNameUpdate: String? = nil, pushNotificationMessage: String? = nil) {
            self.numberOfDeletions = numberOfDeletions
            self.sharingGroupNameUpdate = sharingGroupNameUpdate
            self.pushNotificationMessage = pushNotificationMessage
        }
    }
    
    func commitUploads(serverMasterVersion:MasterVersionInt, sharingGroupUUID: UUID, options: CommitUploadsOptions? = nil, completion:((CommitUploadsResult?, Error?)->(Void))?) {
        let endpoint = ServerEndpoints.doneUploads
        
        // See https://developer.apple.com/reference/foundation/nsurlsessionconfiguration/1408259-timeoutintervalforrequest
        
        var timeoutIntervalForRequest:TimeInterval = Networking.RequestConfiguration.defaultTimeout
        if let numberOfDeletions = options?.numberOfDeletions, numberOfDeletions > 0 {
            timeoutIntervalForRequest += Double(numberOfDeletions) * 5.0
        }
        
        let doneUploadsRequest = DoneUploadsRequest()
        doneUploadsRequest.masterVersion = serverMasterVersion
        doneUploadsRequest.sharingGroupUUID = sharingGroupUUID.uuidString
        doneUploadsRequest.sharingGroupName = options?.sharingGroupNameUpdate
        doneUploadsRequest.pushNotificationMessage = options?.pushNotificationMessage
        
        guard doneUploadsRequest.valid() else {
            completion?(nil, ServerAPIError.couldNotCreateRequest)
            return
        }

        let parameters = doneUploadsRequest.urlParameters()!
        let serverURL = Self.makeURL(forEndpoint: endpoint, baseURL: config.baseURL, parameters: parameters)
        
        let config = Networking.RequestConfiguration(timeoutIntervalForRequest: timeoutIntervalForRequest)

        networking.sendRequestTo(serverURL, method: endpoint.method, configuration: config) { response,  httpStatus, error in
        
            let resultError = self.checkForError(statusCode: httpStatus, error: error)

            if resultError == nil {
                guard let response = response,
                    let doneUploadsResponse = try? DoneUploadsResponse.decode(response) else {
                    completion?(nil, ServerAPIError.nilResponse)
                    return
                }

                if let numberUploads = doneUploadsResponse.numberUploadsTransferred {
                    completion?(CommitUploadsResult.success(numberUploadsTransferred:
                        Int64(numberUploads)), nil)
                }
                else if let masterVersionUpdate = doneUploadsResponse.masterVersionUpdate {
                    completion?(CommitUploadsResult.serverMasterVersionUpdate(masterVersionUpdate), nil)
                } else {
                    completion?(nil, ServerAPIError.noExpectedResultKey)
                }
            }
            else {
                completion?(nil, resultError)
            }
        }
    }
    
    enum DownloadedFile {
        case content(url: URL, appMetaData:AppMetaData?, checkSum:String, cloudStorageType:CloudStorageType, contentsChangedOnServer: Bool)
        
        // The GoneReason should never be userRemoved-- because when a user is removed, their files are marked as deleted in the FileIndex, and thus the files are generally not downloadable.
        case gone(appMetaData:AppMetaData?, cloudStorageType:CloudStorageType, GoneReason)
    }
    
    enum DownloadFileResult {
        case success(DownloadedFile)
        case serverMasterVersionUpdate(Int64)
    }
    
    func downloadFile(fileNamingObject: FilenamingWithAppMetaDataVersion, serverMasterVersion:MasterVersionInt!, sharingGroupUUID: String, completion: @escaping (DownloadFileResult?, Error?)->(Void)) {
        let endpoint = ServerEndpoints.downloadFile
        
        let downloadFileRequest = DownloadFileRequest()
        downloadFileRequest.masterVersion = serverMasterVersion
        downloadFileRequest.fileUUID = fileNamingObject.fileUUID
        downloadFileRequest.fileVersion = fileNamingObject.fileVersion
        downloadFileRequest.appMetaDataVersion = fileNamingObject.appMetaDataVersion
        downloadFileRequest.sharingGroupUUID = sharingGroupUUID
        
        guard downloadFileRequest.valid() else {
            completion(nil, ServerAPIError.couldNotCreateRequest)
            return
        }

        let parameters = downloadFileRequest.urlParameters()!
        let serverURL = Self.makeURL(forEndpoint: endpoint, baseURL: config.baseURL, parameters: parameters)
        
        networking.downloadFile(serverURL, method: endpoint.method) { (resultURL, response, statusCode, error) in
        
            if let error = error {
                completion(nil, error)
                return
            }
            
            guard let response = response else {
                completion(nil, ServerAPIError.nilResponse)
                return
            }
            
            if let resultError = self.checkForError(statusCode: statusCode, error: error) {
                completion(nil, resultError)
                return
            }

            logger.info("response!.allHeaderFields: \(response.allHeaderFields)")
            if let parms = response.allHeaderFields[ServerConstants.httpResponseMessageParams] as? String,
                let jsonDict = self.toJSONDictionary(jsonString: parms) {
                logger.info("jsonDict: \(jsonDict)")
                
                guard let downloadFileResponse = try? DownloadFileResponse.decode(jsonDict) else {
                    completion(nil, ServerAPIError.couldNotObtainHeaderParameters)
                    return
                }
                
                if let masterVersionUpdate = downloadFileResponse.masterVersionUpdate {
                    completion(DownloadFileResult.serverMasterVersionUpdate(masterVersionUpdate), nil)
                    return
                }
                
                guard let cloudStorageTypeRaw = downloadFileResponse.cloudStorageType,
                    let cloudStorageType = CloudStorageType(rawValue: cloudStorageTypeRaw) else {
                    completion(nil, ServerAPIError.couldNotGetCloudStorageType)
                    return
                }
                
                var appMetaData:AppMetaData?
                
                if fileNamingObject.appMetaDataVersion != nil && downloadFileResponse.appMetaData != nil  {
                    appMetaData = AppMetaData(version: fileNamingObject.appMetaDataVersion!, contents: downloadFileResponse.appMetaData!)
                }

                if let goneRaw = downloadFileResponse.gone,
                    let gone = GoneReason(rawValue: goneRaw) {
                    
                    let downloadedFile = DownloadedFile.gone(appMetaData: appMetaData, cloudStorageType: cloudStorageType, gone)
                    completion(.success(downloadedFile), nil)
                }
                else if let checkSum = downloadFileResponse.checkSum,
                    let contentsChanged = downloadFileResponse.contentsChanged {

                    guard let resultURL = resultURL else {
                        completion(nil, ServerAPIError.resultURLObtainedWasNil)
                        return
                    }
                    
                    let hash: String
                    do {
                        hash = try self.delegate.currentHasher(self).hash(forURL: resultURL)
                    } catch (let error) {
                        completion(nil, error)
                        return
                    }
                    
                    guard hash == checkSum else {
                        // Considering this to be a networking error and not something we want to pass up to the client app. This shouldn't happen in normal operation.
                        completion(nil, ServerAPIError.networkingHashMismatch)
                        return
                    }

                    let downloadedFile = DownloadedFile.content(url: resultURL, appMetaData: appMetaData, checkSum: checkSum, cloudStorageType: cloudStorageType, contentsChangedOnServer: contentsChanged)
                    completion(.success(downloadedFile), nil)
                }
                else {
                    completion(nil, ServerAPIError.noExpectedResultKey)
                }
            }
            else {
                completion(nil, ServerAPIError.couldNotObtainHeaderParameters)
            }
        }
    }
}
