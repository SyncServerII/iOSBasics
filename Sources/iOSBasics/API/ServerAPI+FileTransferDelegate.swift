import Foundation
import ServerShared
import iOSShared

extension ServerAPI: FileTransferDelegate {
    func error(_ network: Any, file: Filenaming?, statusCode: Int?, error: Error?) {
    }
    
    func downloadError(_ network: Any, file: Filenaming?, statusCode: Int?, error: Error?) {
    }
    
    func downloadCompleted(_ network: Any, file: Filenaming, url: URL?, response: HTTPURLResponse?, _ statusCode: Int?) {
    
        assert(false)
        /*
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
        */
    }
    
    func uploadError(_ network: Any, file: Filenaming?, statusCode: Int?, error: Error?) {
    }
    
    func uploadCompleted(_ network: Any, file: Filenaming, response: HTTPURLResponse?, responseBody: [String : Any]?, statusCode: Int?) {
    
        if statusCode == HTTPStatus.gone.rawValue,
            let goneReasonRaw = responseBody?[GoneReason.goneReasonKey] as? String,
            let goneReason = GoneReason(rawValue: goneReasonRaw) {
            delegate.uploadCompleted(self, result: .success(UploadFileResult.gone(goneReason)))
            return
        }

        if let resultError = self.checkForError(statusCode: statusCode, error: nil) {
            delegate.uploadError(self, error: resultError)
            return
        }

        if let parms = response?.allHeaderFields[ServerConstants.httpResponseMessageParams] as? String,
            let jsonDict = self.toJSONDictionary(jsonString: parms) {
            logger.info("jsonDict: \(jsonDict)")
            
            guard let uploadFileResponse = try? UploadFileResponse.decode(jsonDict) else {
                delegate.uploadError(self, error: ServerAPIError.couldNotCreateResponse)
                return
            }
            
            if let versionUpdate = uploadFileResponse.masterVersionUpdate {
                let message = UploadFileResult.serverMasterVersionUpdate(versionUpdate)
                logger.info("\(message)")
                delegate.uploadCompleted(self, result: .success(message))
                return
            }
            
            guard let creationDate = uploadFileResponse.creationDate, let updateDate = uploadFileResponse.updateDate else {
                delegate.uploadError(self, error: ServerAPIError.noExpectedResultKey)
                return
            }
            
            delegate.uploadCompleted(self, result: .success(UploadFileResult.success(creationDate: creationDate, updateDate: updateDate)))
        }
        else {
            delegate.uploadError(self, error: ServerAPIError.couldNotObtainHeaderParameters)
        }
    }
}
