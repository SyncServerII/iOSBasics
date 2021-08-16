import ServerShared
import Foundation
import iOSShared

extension ServerAPI {    
    struct IndexResult {
        // This is nil if there are no files.
        let fileIndex: [FileInfo]?
        
        let sharingGroups:[ServerShared.SharingGroup]
    }
    
    func index(sharingGroupUUID: UUID?, completion: @escaping (Swift.Result<IndexResult, Error>)->()) {
        let endpoint = ServerEndpoints.index
        
        let indexRequest = IndexRequest()
        indexRequest.sharingGroupUUID = sharingGroupUUID?.uuidString
        
        guard indexRequest.valid() else {
            completion(.failure(ServerAPIError.couldNotCreateRequest))
            return
        }

        let urlParameters = indexRequest.urlParameters()
        let serverURL = Self.makeURL(forEndpoint: endpoint, baseURL: config.baseURL, parameters: urlParameters)
        
        networking.sendRequestTo(serverURL, method: endpoint.method) { response,  httpStatus, error in
            let resultError = self.checkForError(statusCode: httpStatus, error: error, serverResponse: .dictionary(response))
            
            if let resultError = resultError {
                completion(.failure(resultError))
            }
            else if let response = response,
                let indexResponse = try? IndexResponse.decode(response) {
                let result = IndexResult(fileIndex: indexResponse.fileIndex, sharingGroups: indexResponse.sharingGroups)
                completion(.success(result))
            }
            else {
                completion(.failure(ServerAPIError.couldNotCreateResponse))
            }
        }
    }
    
    struct File {
        enum Version {
            struct FileGroup {
                let fileGroupUUID: UUID
                let objectType: String
            }
            
            case v0(
                url:URL,
                mimeType:MimeType,
                checkSum:String,
                changeResolverName: String?,
                fileGroup: FileGroup?,
                appMetaData:AppMetaData?,
                fileLabel: String
            )
            
            // Must have given a non-nil changeResolverName with v0
            case vN(
                url:URL
            )
        }
        
        let fileTracker: BackgroundCacheFileTracker?
        let fileUUID:String
        let sharingGroupUUID: String
        let deviceUUID:String
        let uploadObjectTrackerId: Int64
        
        // These two must be the same for all N of N files being uploaded for file group, N <= N.
        let batchUUID: UUID
        let batchExpiryInterval:TimeInterval
        
        let version: Version
        
        let informAllButSelf: Bool?
        
        init(fileTracker: BackgroundCacheFileTracker? = nil, fileUUID:String, sharingGroupUUID: String, deviceUUID:String, uploadObjectTrackerId: Int64, batchUUID: UUID, batchExpiryInterval:TimeInterval, version: Version, informAllButSelf: Bool? = nil) {
            self.fileTracker = fileTracker
            self.fileUUID = fileUUID
            self.sharingGroupUUID = sharingGroupUUID
            self.deviceUUID = deviceUUID
            self.uploadObjectTrackerId = uploadObjectTrackerId
            self.batchUUID = batchUUID
            self.batchExpiryInterval = batchExpiryInterval
            self.version = version
            self.informAllButSelf = informAllButSelf
        }
        
        var fileGroupUUID: UUID? {
            guard case .v0(_, _, _, _, let fileGroup, _, _) = version else {
                return nil
            }
            
            return fileGroup?.fileGroupUUID
        }
    }

    // Upload results, if nil is returned, are reported via the ServerAPIDelegate.
    func uploadFile(file:File, uploadIndex: Int32, uploadCount: Int32) -> Error? {
        guard uploadIndex >= 1, uploadIndex <= uploadCount, uploadCount > 0 else {
            return ServerAPIError.badUploadIndex
        }
        
        let endpoint = ServerEndpoints.uploadFile

        logger.info("file.fileUUID: \(String(describing: file.fileUUID))")

        let uploadRequest = UploadFileRequest()
        uploadRequest.fileUUID = file.fileUUID
        uploadRequest.sharingGroupUUID = file.sharingGroupUUID
        uploadRequest.uploadIndex = uploadIndex
        uploadRequest.uploadCount = uploadCount
        uploadRequest.informAllButSelf = file.informAllButSelf
        
        uploadRequest.batchUUID = file.batchUUID.uuidString
        uploadRequest.batchExpiryInterval = file.batchExpiryInterval
        
        let url:URL
        
        switch file.version {
        case .v0(url: let v0URL, mimeType: let mimeType, checkSum: let checkSum, changeResolverName: let changeResolver, fileGroup: let fileGroup, appMetaData: let appMetaData, let fileLabel):
                    
            url = v0URL
            uploadRequest.checkSum = checkSum
            uploadRequest.fileGroupUUID = fileGroup?.fileGroupUUID.uuidString
            uploadRequest.objectType = fileGroup?.objectType
            uploadRequest.mimeType = mimeType.rawValue
            uploadRequest.changeResolverName = changeResolver
            uploadRequest.appMetaData = appMetaData
            uploadRequest.fileLabel = fileLabel
        case .vN(let vNURL):
            url = vNURL
        }

        guard uploadRequest.valid() else {
            let file = FileObject(fileUUID: file.fileUUID, fileVersion: nil, trackerId: file.uploadObjectTrackerId)
            let error = ServerAPIError.couldNotCreateRequest
            logger.error("ServerAPI+Files.uploadFile: \(error)")
            delegate.uploadCompleted(self, file: file, result: .failure(error))
            return error
        }
        
        assert(endpoint.method == .post)
        
        guard let parameters = uploadRequest.urlParameters() else {
            return ServerAPIError.badURLParameters
        }
        
        let serverURL = Self.makeURL(forEndpoint: endpoint, baseURL: config.baseURL, parameters: parameters)
        
        guard let fileTracker = file.fileTracker else {
            return ServerAPIError.generic("Should have a file tracker.")
        }
        
        return networking.upload(fileTracker: fileTracker, fileUUID: file.fileUUID, uploadObjectTrackerId: file.uploadObjectTrackerId, from: url, toServerURL: serverURL, method: endpoint.method)
    }
    
    public enum UploadsResultsId {
        case deferredUploadId(Int64)
        case batchUUID(UUID)
    }
    
    func getUploadsResults(usingId id: UploadsResultsId, completion: @escaping (Result<DeferredUploadStatus?, Error>)->()) {

        let endpoint = ServerEndpoints.getUploadsResults
                
        let request = GetUploadsResultsRequest()
        
        switch id {
        case .batchUUID(let batchUUID):
            request.batchUUID = batchUUID.uuidString

        case .deferredUploadId(let deferredUploadId):
            request.deferredUploadId = deferredUploadId
        }
        
        guard request.valid() else {
            completion(.failure(ServerAPIError.couldNotCreateRequest))
            return
        }
        
        guard let parameters = request.urlParameters() else {
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
                logger.error("getUploadsResults: \(error)")
                completion(.failure(error))
                return
            }
            
            guard let messageResponse = try? GetUploadsResultsResponse.decode(response) else {
                completion(.failure(ServerAPIError.couldNotCreateResponse))
                return
            }

            completion(.success(messageResponse.status))
        }
    }
    
    enum CommitUploadsResult {
        case success(numberUploadsTransferred:Int64)
        case serverMasterVersionUpdate(Int64)
    }
    
    // Download results, if nil is returned, are reported via the ServerAPIDelegate.
    func downloadFile(fileTracker: BackgroundCacheFileTracker, file: Filenaming, sharingGroupUUID: String) -> Error? {
        let endpoint = ServerEndpoints.downloadFile
        
        let downloadFileRequest = DownloadFileRequest()
        downloadFileRequest.fileUUID = file.fileUUID
        downloadFileRequest.fileVersion = file.fileVersion
        downloadFileRequest.sharingGroupUUID = sharingGroupUUID
        
        guard downloadFileRequest.valid() else {
            let error = ServerAPIError.couldNotCreateRequest
            delegate.downloadCompleted(self, file: file, result: .failure(error))
            return error
        }

        let parameters = downloadFileRequest.urlParameters()!
        let serverURL = Self.makeURL(forEndpoint: endpoint, baseURL: config.baseURL, parameters: parameters)
        
        return networking.download(fileTracker: fileTracker, file: file, downloadObjectTrackerId: file.trackerId, fromServerURL: serverURL, method: endpoint.method)
    }
    
    enum DeletionFileResult {
        case fileDeleted(deferredUploadId: Int64)
        case fileAlreadyDeleted
    }
    
    private func prepareDeletion(fileGroupUUID: UUID, sharingGroupUUID: String) throws -> (URL, ServerEndpoint) {
        let endpoint = ServerEndpoints.uploadDeletion
                
        let request = UploadDeletionRequest()
        request.sharingGroupUUID = sharingGroupUUID
        request.fileGroupUUID = fileGroupUUID.uuidString
        
        guard request.valid() else {
            throw ServerAPIError.couldNotCreateRequest
        }
        
        guard let parameters = request.urlParameters() else {
            throw ServerAPIError.couldNotCreateRequest
        }

        let url = Self.makeURL(forEndpoint: endpoint, baseURL: config.baseURL, parameters: parameters)
        
        return (url, endpoint)
    }
    
    func uploadDeletion(fileGroupUUID: UUID, sharingGroupUUID: String, completion: @escaping (Result<DeletionFileResult, Error>)->()) {
        
        let serverURL:URL
        let endpoint: ServerEndpoint
        do {
            let (url, ep) = try prepareDeletion(fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID)
            endpoint = ep
            serverURL = url
        } catch let error {
            completion(.failure(error))
            return
        }

        networking.sendRequestTo(serverURL, method: endpoint.method) { response, httpStatus, error in
           
            guard let response = response else {
                completion(.failure(ServerAPIError.nilResponse))
                return
            }
            
            if let error = self.checkForError(statusCode: httpStatus, error: error, serverResponse: .dictionary(response)) {
                completion(.failure(error))
                return
            }
            
            guard let messageResponse = try? UploadDeletionResponse.decode(response) else {
                completion(.failure(ServerAPIError.couldNotCreateResponse))
                return
            }

            let result:DeletionFileResult
            if let deferredUploadId = messageResponse.deferredUploadId {
                result = .fileDeleted(deferredUploadId: deferredUploadId)
            }
            else {
                result = .fileAlreadyDeleted
            }
            
            completion(.success(result))
        }
    }
    
    class DeletionRequestInfo: Codable {
        var fileGroupUUID: UUID!
    }
    
    // Background upload deletion request. On success, the `backgroundRequestCompleted` will have `SuccessResult.requestInfo` set as `DeletionRequestInfo` coded data.
    // The `trackerId` references a `UploadDeletionTracker`.
    func uploadDeletion(fileGroupUUID: UUID, sharingGroupUUID: String, trackerId: Int64, fileTracker: BackgroundCacheFileTracker) -> Error? {
    
        let requestInfo = DeletionRequestInfo()
        requestInfo.fileGroupUUID = fileGroupUUID
        
        let serverURL:URL
        let endpoint: ServerEndpoint
        let requestInfoData: Data
        
        do {
            let (url, ep) = try prepareDeletion(fileGroupUUID: fileGroupUUID, sharingGroupUUID: sharingGroupUUID)
            endpoint = ep
            serverURL = url
            requestInfoData = try JSONEncoder().encode(requestInfo)
        } catch let error {
            return error
        }

        return networking.sendBackgroundRequestTo(serverURL, method: endpoint.method, uuid: fileGroupUUID, fileTracker: fileTracker, trackerId: trackerId, requestInfo: requestInfoData)
    }
}
