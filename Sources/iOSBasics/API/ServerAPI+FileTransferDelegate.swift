import Foundation
import ServerShared
import iOSShared

extension ServerAPI: FileTransferDelegate {
    func error(_ network: Any, file: Filenaming?, statusCode: Int?, error: Error?) {
        delegate.error(self, error: error)
    }

    func downloadEnded(_ network: Any, file: Filenaming, event: FileTransferDownloadEvent, response: HTTPURLResponse?) {
    
        let url: URL
        
        switch event {
        case .success(let urlResult):
            url = urlResult
        case .failure(error: let error, statusCode: let statusCode, let responseHeaders):
            if let error = error {
                delegate.downloadCompleted(self, file: file, result: .failure(error))
            }
            else {
                let resultError = self.checkForError(statusCode: statusCode, error: error, serverResponse: .dictionary(responseHeaders)) ?? ServerAPIError.generic("Unknown: Failure, but nil error and resultError also nil.")
                delegate.downloadCompleted(self, file: file, result: .failure(resultError))
            }
            return
        }
        
        guard let response = response else {
            delegate.downloadCompleted(self, file: file, result: .failure(ServerAPIError.nilResponse))
            return
        }
        
        logger.info("response.allHeaderFields: \(String(describing: response.allHeaderFields))")

        guard let parms = response.allHeaderFields[ServerConstants.httpResponseMessageParams] as? String,
            let jsonDict = self.toJSONDictionary(jsonString: parms),
            let downloadFileResponse = try? DownloadFileResponse.decode(jsonDict)  else {
            delegate.downloadCompleted(self, file: file, result: .failure(ServerAPIError.couldNotObtainHeaderParameters))
            return
        }
        
        logger.info("Download response jsonDict: \(jsonDict)")
        
        guard let cloudStorageTypeRaw = downloadFileResponse.cloudStorageType,
            let cloudStorageType = CloudStorageType(rawValue: cloudStorageTypeRaw) else {
            delegate.downloadCompleted(self, file: file, result: .failure(ServerAPIError.couldNotGetCloudStorageType))
            return
        }
        
        var appMetaData:AppMetaData?
        
        if let contents = downloadFileResponse.appMetaData {
            appMetaData = AppMetaData(contents: contents)
        }

        guard let fileUUIDString = file.fileUUID,
            let fileUUID = UUID(uuidString: fileUUIDString) else {
            delegate.downloadCompleted(self, file: file, result: .failure(ServerAPIError.badUUID))
            return
        }
            
        if let goneRaw = downloadFileResponse.gone,
            let gone = GoneReason(rawValue: goneRaw) {
            let result = DownloadFileResult.gone(objectTrackerId: file.trackerId, fileUUID: fileUUID, gone)
            delegate.downloadCompleted(self, file: file, result: .success(result))
            return
        }
        
        logger.debug("downloadFileResponse.checkSum: \(String(describing: downloadFileResponse.checkSum))")
        logger.debug("downloadFileResponse.contentsChanged: \(String(describing: downloadFileResponse.contentsChanged))")
        
        if let checkSum = downloadFileResponse.checkSum,
            let contentsChanged = downloadFileResponse.contentsChanged {

            let hash: String
            do {
                let hasher = try self.delegate.hasher(self, forCloudStorageType: cloudStorageType)
                hash = try hasher.hash(forURL: url)
            } catch (let error) {
                delegate.downloadCompleted(self, file: file, result: .failure(error))
                return
            }
            
            guard hash == checkSum else {
                // Considering this to be a networking error and not something we want to pass up to the client app. This shouldn't happen in normal operation.
                delegate.downloadCompleted(self, file: file, result: .failure(ServerAPIError.networkingHashMismatch))
                return
            }
            
            let result = DownloadFileResult.Download(fileUUID: fileUUID, url: url, checkSum: checkSum, contentsChangedOnServer: contentsChanged, appMetaData: appMetaData?.contents)
            delegate.downloadCompleted(self, file: file, result: .success(.success(objectTrackerId: file.trackerId, result)))
        }
        else {
            delegate.downloadCompleted(self, file: file, result: .failure(ServerAPIError.noExpectedResultKey))
        }
    }
    
    func uploadCompleted(_ network: Any, file: Filenaming, response: HTTPURLResponse?, responseBody: [String : Any]?, statusCode: Int?) {
    
        if statusCode == HTTPStatus.gone.rawValue,
            let goneReasonRaw = responseBody?[GoneReason.goneReasonKey] as? String,
            let goneReason = GoneReason(rawValue: goneReasonRaw) {
            
            guard let fileUUIDString = file.fileUUID,
                let _ = UUID(uuidString: fileUUIDString) else {
                delegate.uploadCompleted(self, file: file, result: .failure(ServerAPIError.badUUID))
                return
            }
            
            delegate.uploadCompleted(self, file: file, result: .success(UploadFileResult.gone(goneReason)))
            return
        }

        if let resultError = self.checkForError(statusCode: statusCode, error: nil, serverResponse: .dictionary(responseBody)) {
            logger.error("ServerAPI+FileTransferDelegate.uploadCompleted: \(resultError)")
            delegate.uploadCompleted(self, file: file, result: .failure(resultError))
            return
        }

        if let parms = response?.allHeaderFields[ServerConstants.httpResponseMessageParams] as? String,
            let jsonDict = self.toJSONDictionary(jsonString: parms) {
            logger.info("jsonDict: \(jsonDict)")
            
            guard let uploadFileResponse = try? UploadFileResponse.decode(jsonDict) else {
                delegate.uploadCompleted(self, file: file, result: .failure(ServerAPIError.couldNotCreateResponse))
                return
            }
            
            logger.debug("uploadFileResponse.creationDate: \(String(describing: uploadFileResponse.creationDate))")
            logger.debug("uploadFileResponse.updateDate: \(String(describing: uploadFileResponse.updateDate))")
            logger.debug("uploadFileResponse.allUploadsFinished: \(String(describing: uploadFileResponse.allUploadsFinished))")
                       
            guard let updateDate = uploadFileResponse.updateDate,
                let allUploadsFinished = uploadFileResponse.allUploadsFinished else {
                delegate.uploadCompleted(self, file: file, result: .failure(ServerAPIError.noExpectedResultKey))
                return
            }

            let result = UploadFileResult.Upload(creationDate: uploadFileResponse.creationDate, updateDate: updateDate, uploadsFinished: allUploadsFinished, deferredUploadId: uploadFileResponse.deferredUploadId)
            
            delegate.uploadCompleted(self, file: file, result: .success(.success(result)))
        }
        else {
            delegate.uploadCompleted(self, file: file, result: .failure(ServerAPIError.couldNotObtainHeaderParameters))
        }
    }
    
    func backgroundRequestCompleted(_ network: Any, url: URL?, trackerId: Int64, response: HTTPURLResponse?, requestInfo: Data?, statusCode: Int?) {

        if statusCode == HTTPStatus.gone.rawValue {
            delegate.backgroundRequestCompleted(self, result: .success(.gone(objectTrackerId: trackerId)))
            return
        }

        if let resultError = self.checkForError(statusCode: statusCode, error: nil, serverResponse: .file(url)) {
            logger.error("backgroundRequestCompleted: \(resultError)")
            delegate.backgroundRequestCompleted(self, result: .failure(resultError))
            return
        }
        
        guard let url = url else {
            delegate.backgroundRequestCompleted(self, result: .failure(ServerAPIError.resultURLObtainedWasNil))
            return
        }
        
        let result = BackgroundRequestResult.SuccessResult(serverResponse: url, requestInfo: requestInfo)
        delegate.backgroundRequestCompleted(self, result: .success(.success(objectTrackerId: trackerId, result)))
    }
}
