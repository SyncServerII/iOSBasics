import ServerShared
import Foundation
import iOSShared

extension ServerAPI {    
    struct IndexResult {
        // This is nil if there are no files.
        let fileIndex: [FileInfo]?
        
        let sharingGroups:[SharingGroup]
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
            enum Source {
                case url(URL)
                case data(Data)
            }
            case v0(
                source:Source,
                mimeType:MimeType,
                checkSum:String,
                changeResolverName: String?,
                fileGroupUUID:String?,
                appMetaData:AppMetaData?
            )
            
            // Must have given a non-nil changeResolverName with v0
            case vN(
                change: Data
            )
        }
        
        let fileUUID:String
        let sharingGroupUUID: String
        let deviceUUID:String
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
        
        var url:URL!
        var data: Data?
        
        switch file.version {
        case .v0(source: let source, mimeType: let mimeType, checkSum: let checkSum, changeResolverName: let changeResolver, fileGroupUUID: let fileGroupUUID, appMetaData: let appMetaData):
        
            switch source {
            case .data(let d):
                data = d
            case .url(let u):
                url = u
            }
            
            uploadRequest.checkSum = checkSum
            uploadRequest.fileGroupUUID = fileGroupUUID
            uploadRequest.mimeType = mimeType.rawValue
            uploadRequest.changeResolverName = changeResolver
            uploadRequest.appMetaData = appMetaData
        case .vN(let d):
            data = d
        }

        guard uploadRequest.valid() else {
            let error = ServerAPIError.couldNotCreateRequest
            delegate.uploadCompleted(self, result: .failure(error))
            return error
        }
        
        assert(endpoint.method == .post)
        
        guard let parameters = uploadRequest.urlParameters() else {
            return ServerAPIError.badURLParameters
        }
        
        let serverURL = Self.makeURL(forEndpoint: endpoint, baseURL: config.baseURL, parameters: parameters)
        
        if let data = data {
            return networking.upload(fileUUID: file.fileUUID, from: .data(data), toServerURL: serverURL, method: endpoint.method)
        } else if let url = url {
            return networking.upload(fileUUID: file.fileUUID, from: .localFile(url), toServerURL: serverURL, method: endpoint.method)
        }
        
        return ServerAPIError.noExpectedResultKey
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
        
        return networking.download(file: file, fromServerURL: serverURL, method: endpoint.method)
    }
}
