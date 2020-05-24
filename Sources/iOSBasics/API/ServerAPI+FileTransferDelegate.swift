import Foundation
import ServerShared
import iOSShared

extension ServerAPI: FileTransferDelegate {
    func error(_ network: Any, file: Filenaming?, statusCode: Int?, error: Error?) {
        assert(false)
    }
    
    func downloadError(_ network: Any, file: FilenamingWithAppMetaDataVersion?, statusCode: Int?, error: Error?) {
        assert(false)
    }
    
    func downloadCompleted(_ network: Any, file: FilenamingWithAppMetaDataVersion, url: URL?, response: HTTPURLResponse?, _ statusCode: Int?) {

        if let resultError = self.checkForError(statusCode: statusCode, error: nil) {
            delegate.downloadCompleted(self, result: .failure(resultError))
            return
        }
        
        guard let response = response else {
            delegate.downloadCompleted(self, result: .failure(ServerAPIError.nilResponse))
            return
        }
        
        logger.info("response.allHeaderFields: \(String(describing: response.allHeaderFields))")

        guard let parms = response.allHeaderFields[ServerConstants.httpResponseMessageParams] as? String,
            let jsonDict = self.toJSONDictionary(jsonString: parms),
            let downloadFileResponse = try? DownloadFileResponse.decode(jsonDict)  else {
            delegate.downloadCompleted(self, result: .failure(ServerAPIError.couldNotObtainHeaderParameters))
            return
        }
        
        logger.info("Download response jsonDict: \(jsonDict)")
        
        if let masterVersionUpdate = downloadFileResponse.masterVersionUpdate {
            delegate.downloadCompleted(self, result: .success(DownloadFileResult.serverMasterVersionUpdate(masterVersionUpdate)))
            return
        }
        
        guard let cloudStorageTypeRaw = downloadFileResponse.cloudStorageType,
            let cloudStorageType = CloudStorageType(rawValue: cloudStorageTypeRaw) else {
            delegate.downloadCompleted(self, result: .failure(ServerAPIError.couldNotGetCloudStorageType))
            return
        }
        
        var appMetaData:AppMetaData?
        
        if let appMetaDataVersion = file.appMetaDataVersion,
            let contents = downloadFileResponse.appMetaData  {
            appMetaData = AppMetaData(version: appMetaDataVersion, contents: contents)
        }

        if let goneRaw = downloadFileResponse.gone,
            let gone = GoneReason(rawValue: goneRaw) {
            let result = DownloadFileResult.gone(appMetaData: appMetaData, cloudStorageType: cloudStorageType, gone)
            delegate.downloadCompleted(self, result: .success(result))
        }
        else if let checkSum = downloadFileResponse.checkSum,
            let contentsChanged = downloadFileResponse.contentsChanged {

            guard let url = url else {
                delegate.downloadCompleted(self, result: .failure(ServerAPIError.resultURLObtainedWasNil))
                return
            }
            
            let hash: String
            do {
                hash = try self.delegate.currentHasher(self).hash(forURL: url)
            } catch (let error) {
                delegate.downloadCompleted(self, result: .failure(error))
                return
            }
            
            guard hash == checkSum else {
                // Considering this to be a networking error and not something we want to pass up to the client app. This shouldn't happen in normal operation.
                delegate.downloadCompleted(self, result: .failure(ServerAPIError.networkingHashMismatch))
                return
            }
            
            let result = DownloadFileResult.success(url: url, appMetaData: appMetaData, checkSum: checkSum, cloudStorageType: cloudStorageType, contentsChangedOnServer: contentsChanged)
            delegate.downloadCompleted(self, result: .success(result))
        }
        else {
            delegate.downloadCompleted(self, result: .failure(ServerAPIError.noExpectedResultKey))
        }
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
            delegate.uploadCompleted(self, result: .failure(resultError))
            return
        }

        if let parms = response?.allHeaderFields[ServerConstants.httpResponseMessageParams] as? String,
            let jsonDict = self.toJSONDictionary(jsonString: parms) {
            logger.info("jsonDict: \(jsonDict)")
            
            guard let uploadFileResponse = try? UploadFileResponse.decode(jsonDict) else {
                delegate.uploadCompleted(self, result: .failure(ServerAPIError.couldNotCreateResponse))
                return
            }
            
            if let versionUpdate = uploadFileResponse.masterVersionUpdate {
                let message = UploadFileResult.serverMasterVersionUpdate(versionUpdate)
                logger.info("\(message)")
                delegate.uploadCompleted(self, result: .success(message))
                return
            }
            
            guard let creationDate = uploadFileResponse.creationDate, let updateDate = uploadFileResponse.updateDate else {
                delegate.uploadCompleted(self, result: .failure(ServerAPIError.noExpectedResultKey))
                return
            }
            
            delegate.uploadCompleted(self, result: .success(UploadFileResult.success(creationDate: creationDate, updateDate: updateDate)))
        }
        else {
            delegate.uploadCompleted(self, result: .failure(ServerAPIError.couldNotObtainHeaderParameters))
        }
    }
}
