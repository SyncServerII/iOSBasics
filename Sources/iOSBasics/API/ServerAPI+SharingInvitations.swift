import ServerShared
import Foundation
import iOSShared

extension ServerAPI {
    // The non-error result is the sharingInvitationUUID.
    func createSharingInvitation(withPermission permission:Permission, sharingGroupUUID: UUID, numberAcceptors: UInt, allowSocialAcceptance: Bool, expiryDuration: TimeInterval = ServerConstants.sharingInvitationExpiryDuration, completion: @escaping (Result<UUID, Error>)->()) {
    
        let endpoint = ServerEndpoints.createSharingInvitation

        let invitationRequest = CreateSharingInvitationRequest()
        invitationRequest.permission = permission
        invitationRequest.sharingGroupUUID = sharingGroupUUID.uuidString
        invitationRequest.allowSocialAcceptance = allowSocialAcceptance
        invitationRequest.numberOfAcceptors = numberAcceptors
        invitationRequest.expiryDuration = expiryDuration
                
        guard let parameters = invitationRequest.urlParameters() else {
            completion(.failure(ServerAPIError.couldNotCreateRequest))
            return
        }
        
        let serverURL = Self.makeURL(forEndpoint: endpoint, baseURL: config.baseURL, parameters: parameters)

        networking.sendRequestTo(serverURL, method: endpoint.method) { [weak self] response, httpStatus, error in
            guard let self = self else { return }

            if let resultError = self.checkForError(statusCode: httpStatus, error: error, serverResponse: .dictionary(response)) {
                completion(.failure(resultError))
                return
            }
            
            if let response = response,
                let invitationResponse = try? CreateSharingInvitationResponse.decode(response),
                let sharingInvitationUUIDString = invitationResponse.sharingInvitationUUID,
                let sharingInvitationUUID = UUID(uuidString: sharingInvitationUUIDString) {
                    completion(.success(sharingInvitationUUID))
            }
            else {
                completion(.failure(ServerAPIError.couldNotCreateResponse))
            }
        }
    }
    
    // Some accounts return an access token after sign-in (e.g., Facebook's long-lived access token).
    // When redeeming a sharing invitation for an owning user account type that requires a cloud folder, you must give a cloud folder in the redeeming request.
    // The error is SyncServerError.socialAcceptanceNotAllowed when attmepting to redeem with a social account, but the invitation doesn't allow this.
    func redeemSharingInvitation(sharingInvitationUUID:UUID, cloudFolderName: String?, emailAddress: String? = nil, completion: @escaping (Result<RedeemResult, Error>)->()) {
        let endpoint = ServerEndpoints.redeemSharingInvitation

        let redeemRequest = RedeemSharingInvitationRequest()
        redeemRequest.sharingInvitationUUID = sharingInvitationUUID.uuidString
        redeemRequest.cloudFolderName = cloudFolderName
        redeemRequest.emailAddress = emailAddress

        guard let parameters = redeemRequest.urlParameters() else {
            completion(.failure(ServerAPIError.couldNotCreateRequest))
            return
        }
        
        let serverURL = Self.makeURL(forEndpoint: endpoint, baseURL: config.baseURL, parameters: parameters)
        
        networking.sendRequestTo(serverURL, method: endpoint.method) { [weak self] response, httpStatus, error in
            guard let self = self else { return }

            if httpStatus == HTTPStatus.forbidden.rawValue {
                completion(.failure(ServerAPIError.socialAcceptanceNotAllowed))
                return
            }
            
            if let resultError = self.checkForError(statusCode: httpStatus, error: error, serverResponse: .dictionary(response)) {
                completion(.failure(resultError))
                return
            }

            if let response = response,
                let invitationResponse = try? RedeemSharingInvitationResponse.decode(response),
                let sharingGroupUUIDString = invitationResponse.sharingGroupUUID,
                let sharingGroupUUID = UUID(uuidString: sharingGroupUUIDString),
                let userCreated = invitationResponse.userCreated,
                let userId = invitationResponse.userId {
                
                let accessToken = response[ServerConstants.httpResponseOAuth2AccessTokenKey] as? String
                let result = RedeemResult(accessToken: accessToken, sharingGroupUUID: sharingGroupUUID, userId: userId, userCreated: userCreated)
                completion(.success(result))
            }
            else {
                completion(.failure(ServerAPIError.couldNotCreateResponse))
            }
        }
    }

    // This endpoint doesn't require the user to be signed in.
    func getSharingInvitationInfo(sharingInvitationUUID: UUID, completion: @escaping (Result<SharingInvitationInfo, Error>)->()) {
        let endpoint = ServerEndpoints.getSharingInvitationInfo
        
        let getSharingInfoRequest = GetSharingInvitationInfoRequest()
        getSharingInfoRequest.sharingInvitationUUID = sharingInvitationUUID.uuidString
        
        guard getSharingInfoRequest.valid() else {
            completion(.failure(ServerAPIError.couldNotCreateRequest))
            return
        }
        
        guard let parameters = getSharingInfoRequest.urlParameters() else {
            completion(.failure(ServerAPIError.couldNotCreateRequest))
            return
        }
        
        let serverURL = Self.makeURL(forEndpoint: endpoint, baseURL: config.baseURL, parameters: parameters)
        
        networking.sendRequestTo(serverURL, method: endpoint.method, authenticationLevelNone: true) { [weak self] response, httpStatus, error in
            guard let self = self else { return }
            
            if httpStatus == HTTPStatus.gone.rawValue {
                completion(.success(.noInvitationFound))
                return
            }
            
            if let resultError = self.checkForError(statusCode: httpStatus, error: error, serverResponse: .dictionary(response)) {
                completion(.failure(resultError))
            }
            else {
                if let response = response,
                    let getSharingInvitationResponse = try? GetSharingInvitationInfoResponse.decode(response),
                    let permission = getSharingInvitationResponse.permission,
                    let allowsSharingAcceptance = getSharingInvitationResponse.allowSocialAcceptance {
                    let info = Invitation(code: sharingInvitationUUID.uuidString, permission: permission, allowsSocialSharing: allowsSharingAcceptance)
                    completion(.success(.invitation(info)))
                }
                else {
                    completion(.failure(ServerAPIError.couldNotCreateResponse))
                }
            }
        }
    }
}

