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
            let resultError = self.checkForError(statusCode: httpStatus, error: error)
            
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
        
        let fileUUID:String
        let sharingGroupUUID: String
        let deviceUUID:String
        let uploadObjectTrackerId: Int64
        let version: Version
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
            delegate.uploadCompleted(self, file: file, result: .failure(error))
            return error
        }
        
        assert(endpoint.method == .post)
        
        guard let parameters = uploadRequest.urlParameters() else {
            return ServerAPIError.badURLParameters
        }
        
        let serverURL = Self.makeURL(forEndpoint: endpoint, baseURL: config.baseURL, parameters: parameters)
        
        return networking.upload(fileUUID: file.fileUUID, uploadObjectTrackerId: file.uploadObjectTrackerId, from: url, toServerURL: serverURL, method: endpoint.method)
    }
    
    func getUploadsResults(deferredUploadId: Int64, completion: @escaping (Result<DeferredUploadStatus?, Error>)->()) {

        let endpoint = ServerEndpoints.getUploadsResults
                
        let request = GetUploadsResultsRequest()
        request.deferredUploadId = deferredUploadId
        
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
            
            if let error = self.checkForError(statusCode: httpStatus, error: error) {
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
    func downloadFile(file: Filenaming, sharingGroupUUID: String) -> Error? {
        let endpoint = ServerEndpoints.downloadFile
        
        let downloadFileRequest = DownloadFileRequest()
        downloadFileRequest.fileUUID = file.fileUUID
        downloadFileRequest.fileVersion = file.fileVersion
        downloadFileRequest.sharingGroupUUID = sharingGroupUUID
        
        guard downloadFileRequest.valid() else {
            let error = ServerAPIError.couldNotCreateRequest
            delegate.downloadCompleted(self, result: .failure(error))
            return error
        }

        let parameters = downloadFileRequest.urlParameters()!
        let serverURL = Self.makeURL(forEndpoint: endpoint, baseURL: config.baseURL, parameters: parameters)
        
        return networking.download(file: file, downloadObjectTrackerId: file.trackerId, fromServerURL: serverURL, method: endpoint.method)
    }
    
    enum DeletionFile {
        enum UUIDType: String, Codable {
            case fileUUID
            case fileGroupUUID
        }
        
        case fileUUID(String)
        case fileGroupUUID(String)
        
        init(uuid: UUID, type: UUIDType) {
            switch type {
            case .fileUUID:
                self = .fileUUID(uuid.uuidString)
            case .fileGroupUUID:
                self = .fileGroupUUID(uuid.uuidString)
            }
        }
        
        var uuidString:String {
            switch self {
            case .fileUUID(let uuid):
                return uuid
            case .fileGroupUUID(let uuid):
                return uuid
            }
        }
        
        var uuidType: UUIDType {
            switch self {
            case .fileUUID:
                return .fileUUID
            case .fileGroupUUID:
                return .fileGroupUUID
            }
        }
    }
    
    enum DeletionFileResult {
        case fileDeleted(deferredUploadId: Int64)
        case fileAlreadyDeleted
    }
    
    private func prepareDeletion(file: DeletionFile, sharingGroupUUID: String) throws -> (URL, ServerEndpoint) {
        let endpoint = ServerEndpoints.uploadDeletion
                
        let request = UploadDeletionRequest()
        request.sharingGroupUUID = sharingGroupUUID
        
        switch file {
        case .fileUUID(let fileUUID):
            request.fileUUID = fileUUID
        case .fileGroupUUID(let fileGroupUUID):
            request.fileGroupUUID = fileGroupUUID
        }
        
        guard request.valid() else {
            throw ServerAPIError.couldNotCreateRequest
        }
        
        guard let parameters = request.urlParameters() else {
            throw ServerAPIError.couldNotCreateRequest
        }

        let url = Self.makeURL(forEndpoint: endpoint, baseURL: config.baseURL, parameters: parameters)
        
        return (url, endpoint)
    }
    
    func uploadDeletion(file: DeletionFile, sharingGroupUUID: String, completion: @escaping (Result<DeletionFileResult, Error>)->()) {
        
        let serverURL:URL
        let endpoint: ServerEndpoint
        do {
            let (url, ep) = try prepareDeletion(file: file, sharingGroupUUID: sharingGroupUUID)
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
            
            if let error = self.checkForError(statusCode: httpStatus, error: error) {
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
        var uuid: UUID!
        var uuidType: DeletionFile.UUIDType!
    }
    
    // Background upload deletion request. On success, the `backgroundRequestCompleted` will have `SuccessResult.requestInfo` set as `DeletionRequestInfo` coded data.
    // The `trackerId` references a `UploadDeletionTracker`.
    func uploadDeletion(file: DeletionFile, sharingGroupUUID: String, trackerId: Int64) -> Error? {
    
        guard let uuid = UUID(uuidString: file.uuidString) else {
            return ServerAPIError.badUUID
        }
    
        let requestInfo = DeletionRequestInfo()
        requestInfo.uuid = uuid
        requestInfo.uuidType = file.uuidType
    
        let serverURL:URL
        let endpoint: ServerEndpoint
        let requestInfoData: Data
        
        do {
            let (url, ep) = try prepareDeletion(file: file, sharingGroupUUID: sharingGroupUUID)
            endpoint = ep
            serverURL = url
            requestInfoData = try JSONEncoder().encode(requestInfo)
        } catch let error {
            return error
        }

        return networking.sendBackgroundRequestTo(serverURL, method: endpoint.method, uuid: uuid, trackerId: trackerId, requestInfo: requestInfoData)
    }
}
