//
//  ServerAPI+Notifications.swift
//  
//
//  Created by Christopher G Prince on 1/14/21.
//

import ServerShared
import Foundation
import iOSShared

extension ServerAPI {
    func sendPushNotification(_ message: String, sharingGroupUUID: UUID, completion: @escaping (Error?)->()) {
    
        let endpoint = ServerEndpoints.sendPushNotifications

        let pushNotificationRequest = SendPushNotificationsRequest()
        pushNotificationRequest.sharingGroupUUID = sharingGroupUUID.uuidString
        pushNotificationRequest.message = message

        guard pushNotificationRequest.valid() else {
            completion(ServerAPIError.couldNotCreateRequest)
            return
        }
        
        guard let parameters = pushNotificationRequest.urlParameters() else {
            completion(ServerAPIError.couldNotCreateRequest)
            return
        }

        let serverURL = Self.makeURL(forEndpoint: endpoint, baseURL: config.baseURL, parameters: parameters)

        networking.sendRequestTo(serverURL, method: endpoint.method) { [weak self] response, httpStatus, error in
            guard let self = self else { return }
            
            if let resultError = self.checkForError(statusCode: httpStatus, error: error) {
                completion(resultError)
            }
            else {
                if let response = response,
                    let _ = try? SendPushNotificationsResponse.decode(response) {
                    completion(nil)
                }
                else {
                    completion(ServerAPIError.couldNotCreateResponse)
                }
            }
        }
    }
}
