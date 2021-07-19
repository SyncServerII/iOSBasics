//
//  ServerAPI+SharingGroups.swift
//  
//
//  Created by Christopher G Prince on 9/19/20.
//

import Foundation
import ServerShared
import iOSShared

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
            
            if let resultError = self.checkForError(statusCode: httpStatus, error: error, serverResponse: .dictionary(response)) {
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
    
    func updateSharingGroup(sharingGroup: UUID, newSharingGroupName: String?, completion:@escaping (Error?)->()) {
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
            
            if let resultError = self.checkForError(statusCode: httpStatus, error: error, serverResponse: .dictionary(response)) {
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
            
            if let resultError = self.checkForError(statusCode: httpStatus, error: error, serverResponse: .dictionary(response)) {
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
    
    func moveFileGroups(_ fileGroups: [UUID], usersThatMustBeInDestination: Set<UserId>? = nil, fromSourceSharingGroup sourceSharingGroup: UUID, toDestinationSharingGroup destinationSharingGroup: UUID, completion:@escaping (Swift.Result<MoveFileGroupsResponse, Error>)->()) {
        let endpoint = ServerEndpoints.moveFileGroupsFromSourceSharingGroupToDest
        
        let request = MoveFileGroupsRequest()
        request.sourceSharingGroupUUID = sourceSharingGroup.uuidString
        request.destinationSharingGroupUUID = destinationSharingGroup.uuidString
        request.fileGroupUUIDs = fileGroups.map { $0.uuidString }
        request.usersThatMustBeInDestination = usersThatMustBeInDestination
        
        guard request.reallyValid() else {
            completion(.failure(ServerAPIError.couldNotCreateRequest))
            return
        }
        
        let data: Data
        do {
            data = try JSONEncoder().encode(request)
        } catch let error {
            logger.error("Could not encode MoveFileGroupsRequest: \(error)")
            completion(.failure(ServerAPIError.couldNotCreateRequest))
            return
        }
        
        let serverURL = Self.makeURL(forEndpoint: endpoint, baseURL: config.baseURL)
        
        let requestConfiguration = Networking.RequestConfiguration(dataToUpload: data)
        
        networking.sendRequestTo(serverURL, method: endpoint.method, configuration: requestConfiguration) { [weak self] response, httpStatus, error in
            guard let self = self else { return }
            
            if let resultError = self.checkForError(statusCode: httpStatus, error: error, serverResponse: .dictionary(response)) {
                completion(.failure(resultError))
            }
            else {
                if let response = response,
                    let fileGroupsResponse = try? MoveFileGroupsResponse.decode(response) {
                    completion(.success(fileGroupsResponse))
                }
                else {
                    completion(.failure(ServerAPIError.couldNotCreateResponse))
                }
            }
        }
    }
}
