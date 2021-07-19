//
//  SyncServer+SharingGroups+Move.swift
//  
//
//  Created by Christopher G Prince on 7/9/21.
//

import Foundation
import ServerShared
import SQLite
import iOSShared

extension SyncServer {
    enum MoveFileGroupsError: Error {
        case noFileGroups
        case noObject
    }
    
    func moveFileGroupsHelper(_ fileGroups: [UUID], usersThatMustBeInDestination: Set<UserId>? = nil, fromSourceSharingGroup sourceSharingGroup: UUID, toDestinationSharingGroup destinationSharingGroup:UUID, sourcePushNotificationMessage: String? = nil, destinationPushNotificationMessage: String? = nil, completion:@escaping (MoveFileGroupsResult)->()) throws {
    
        guard fileGroups.count > 0 else {
            throw MoveFileGroupsError.noFileGroups
        }
    
        // Let the server:
        // * Check if the sharing groups and file groups are valid.
        // * Do admin rights checks on the source and dest sharing group.
        
        // Make sure there are no uploads or deletions queued for these file groups.
        
        var deletionExpression:Expression<Bool>!
        var uploadExpression:Expression<Bool>!

        for fileGroup in fileGroups {
            if deletionExpression == nil {
                deletionExpression = UploadDeletionTracker.uuidField.description == fileGroup
                uploadExpression = UploadObjectTracker.fileGroupUUIDField.description == fileGroup
            }
            else {
                deletionExpression = deletionExpression || UploadDeletionTracker.uuidField.description == fileGroup
                uploadExpression = uploadExpression || UploadObjectTracker.fileGroupUUIDField.description == fileGroup
            }
        }
                
        let deletions = try UploadDeletionTracker.fetch(db: db, where: deletionExpression)
        guard deletions.count == 0 else {
            completion(.currentDeletions)
            return
        }
        
        let uploads = try UploadObjectTracker.fetch(db: db, where: uploadExpression)
        guard uploads.count == 0 else {
            completion(.currentUploads)
            return
        }
        
        // After a successful move, change the sharing group of the file groups.

        api.moveFileGroups(fileGroups, usersThatMustBeInDestination: usersThatMustBeInDestination, fromSourceSharingGroup: sourceSharingGroup, toDestinationSharingGroup: destinationSharingGroup) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let response):
                switch response.result {
                case .failedWithNotAllOwnersInTarget:
                    completion(.failedWithNotAllOwnersInTarget)
                    
                case .failedWithUserConstraintNotSatisfied:
                    completion(.failedWithUserConstraintNotSatisfied)
                    
                case .success:
                    do {
                        try self.changeSharingGroup(fileGroups: fileGroups, toDestinationSharingGroup: destinationSharingGroup)
                        self.send(pushNotificationMessage: sourcePushNotificationMessage, sharingGroupUUID: sourceSharingGroup)
                        self.send(pushNotificationMessage: destinationPushNotificationMessage, sharingGroupUUID: destinationSharingGroup)
                        completion(.success)
                    }
                    catch let error {
                        logger.error("Failed changing sharing groups: \(error)")
                        completion(.error(error))
                    }
                    
                case .none:
                    completion(.error(nil))
                }
                
            case .failure(let error):
                completion(.error(error))
            }
        }
    }
    
    private func changeSharingGroup(fileGroups: [UUID], toDestinationSharingGroup destinationSharinGroup:UUID) throws {
        for fileGroup in fileGroups {
            guard let objectEntry = try DirectoryObjectEntry.fetchSingleRow(db: db, where: DirectoryObjectEntry.fileGroupUUIDField.description == fileGroup) else {
                throw MoveFileGroupsError.noObject
            }
            
            try objectEntry.update(setters: DirectoryObjectEntry.sharingGroupUUIDField.description <- destinationSharinGroup)
        }
    }
    
    // Does not send a push notification if `pushNotificationMessage` is nil.
    private func send(pushNotificationMessage: String?, sharingGroupUUID: UUID) {
        if let pushNotificationMessage = pushNotificationMessage {
            api.sendPushNotification(pushNotificationMessage, sharingGroupUUID: sharingGroupUUID) { [weak self] error in
                if let error = error {
                    self?.reportError(SyncServerError.internalError("Failed sending push notification"))
                    logger.error("\(error)")
                }
            }
        }
    }
}
