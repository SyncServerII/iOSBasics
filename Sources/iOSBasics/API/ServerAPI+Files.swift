import ServerShared
import Foundation
import iOSShared

extension ServerAPI {
    struct File {
        enum Version {
            case v0(
                localURL:URL,
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
        
        switch file.version {
        case .v0(localURL: let localURL, mimeType: let mimeType, checkSum: let checkSum, changeResolverName: let changeResolver, fileGroupUUID: let fileGroupUUID, appMetaData: let appMetaData):
            url = localURL
            uploadRequest.checkSum = checkSum
            uploadRequest.fileGroupUUID = fileGroupUUID
            uploadRequest.mimeType = mimeType.rawValue
            uploadRequest.changeResolverName = changeResolver
            uploadRequest.appMetaData = appMetaData
        case .vN:
            break
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
        
        switch file.version {
        case .v0:
            return networking.upload(fileUUID: file.fileUUID, from: .localFile(url), toServerURL: serverURL, method: endpoint.method)
        case .vN(change: let data):
            return networking.upload(fileUUID: file.fileUUID, from: .data(data), toServerURL: serverURL, method: endpoint.method)
        }
    }
    
    enum CommitUploadsResult {
        case success(numberUploadsTransferred:Int64)
        case serverMasterVersionUpdate(Int64)
    }

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
