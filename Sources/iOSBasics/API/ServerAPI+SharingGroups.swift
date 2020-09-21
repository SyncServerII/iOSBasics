//
//  File.swift
//  
//
//  Created by Christopher G Prince on 9/19/20.
//

import Foundation
import ServerShared

extension ServerAPI {
    func createSharingGroup(sharingGroup: UUID, sharingGroupName: String? = nil, completion: @escaping (Error?)->()) {
        let endpoint = ServerEndpoints.createSharingGroup
                
        let createSharingGroup = CreateSharingGroupRequest()
        createSharingGroup.sharingGroupName = sharingGroupName
        createSharingGroup.sharingGroupUUID = sharingGroup.uuidString
        
        guard createSharingGroup.valid() else {
            completion(ServerAPIError.couldNotCreateRequest)
            return
        }
        
        guard let parameters = createSharingGroup.urlParameters() else {
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
                    let _ = try? CreateSharingGroupResponse.decode(response) {
                    completion(nil)
                }
                else {
                    completion(ServerAPIError.couldNotCreateResponse)
                }
            }
        }
    }
    
    func updateSharingGroup(sharingGroup: UUID, newSharingGroupName: String, completion:@escaping (Error?)->()) {
        let endpoint = ServerEndpoints.updateSharingGroup
                
        let updateSharingGroup = UpdateSharingGroupRequest()
        updateSharingGroup.sharingGroupName = newSharingGroupName
        updateSharingGroup.sharingGroupUUID = sharingGroup.uuidString
        
        guard updateSharingGroup.valid() else {
            completion(ServerAPIError.couldNotCreateRequest)
            return
        }
        
        guard let parameters = updateSharingGroup.urlParameters() else {
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
                    let _ = try? UpdateSharingGroupResponse.decode(response) {
                    completion(nil)
                }
                else {
                    completion(ServerAPIError.couldNotCreateResponse)
                }
            }
        }
    }
    
    func removeFromSharingGroup(sharingGroup: UUID, completion:@escaping (Error?)->()) {
        let endpoint = ServerEndpoints.removeUserFromSharingGroup
                
        let removeUserFromSharingGroup = RemoveUserFromSharingGroupRequest()
        removeUserFromSharingGroup.sharingGroupUUID = sharingGroup.uuidString
        
        guard removeUserFromSharingGroup.valid() else {
            completion(ServerAPIError.couldNotCreateRequest)
            return
        }
        
        guard let parameters = removeUserFromSharingGroup.urlParameters() else {
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
                    let _ = try? RemoveUserFromSharingGroupResponse.decode(response) {
                    completion(nil)
                }
                else {
                    completion(ServerAPIError.couldNotCreateResponse)
                }
            }
        }
    }
}
