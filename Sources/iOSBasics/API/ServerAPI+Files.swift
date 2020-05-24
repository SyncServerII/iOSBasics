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
    
    // Set undelete = true in order to do an upload undeletion. The server file must already have been deleted. The meaning is to upload a new file version for a file that has already been deleted on the server. The use case is for conflict resolution-- when a download deletion and a file upload are taking place at the same time, and the client want's its upload to take priority over the download deletion.
    func uploadFile(file:File, serverMasterVersion:MasterVersionInt, undelete:Bool = false) -> Error? {
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
            let error = ServerAPIError.couldNotCreateRequest
            delegate.uploadCompleted(self, result: .failure(error))
            return error
        }
        
        uploadRequest.appMetaData = file.appMetaData
        
        assert(endpoint.method == .post)
        
        let parameters = uploadRequest.urlParameters()!
        let serverURL = Self.makeURL(forEndpoint: endpoint, baseURL: config.baseURL, parameters: parameters)
        
        return networking.upload(file: file, fromLocalURL: file.localURL, toServerURL: serverURL, method: endpoint.method)
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
    
    func downloadFile(file: FilenamingWithAppMetaDataVersion, serverMasterVersion:MasterVersionInt!, sharingGroupUUID: String) -> Error? {
        let endpoint = ServerEndpoints.downloadFile
        
        let downloadFileRequest = DownloadFileRequest()
        downloadFileRequest.masterVersion = serverMasterVersion
        downloadFileRequest.fileUUID = file.fileUUID
        downloadFileRequest.fileVersion = file.fileVersion
        downloadFileRequest.appMetaDataVersion = file.appMetaDataVersion
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
