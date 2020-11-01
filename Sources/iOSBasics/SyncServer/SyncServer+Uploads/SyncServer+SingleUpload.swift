//
//  SyncServer+SingleUpload.swift
//  
//
//  Created by Christopher G Prince on 9/6/20.
//

import Foundation
import ServerShared
import SQLite

extension SyncServer {
    // Assumes that an UploadFileTracker has already been created for the file referenced by fileUUID.
    // uploadIndex >= 1 and uploadIndex <= uploadCount
    func singleUpload(objectType: DeclaredObjectModel, objectTracker: UploadObjectTracker, objectEntry: DirectoryObjectEntry, fileLabel: String, fileUUID uuid: UUID, v0Upload: Bool, uploadIndex: Int32, uploadCount: Int32) throws {
    
        let fileDeclaration = try objectType.getFile(with: fileLabel)
    
        guard let objectTrackerId = objectTracker.id else {
            throw SyncServerError.internalError("Could not get object tracker id")
        }
            
        guard let fileTracker = try UploadFileTracker.fetchSingleRow(db: db, where:
            uuid == UploadFileTracker.fileUUIDField.description &&
            objectTrackerId == UploadFileTracker.uploadObjectTrackerIdField.description),
            let checkSum = fileTracker.checkSum,
            let localURL = fileTracker.localURL else {
            throw SyncServerError.internalError("Could not get upload file tracker: \(uuid)")
        }
        
        let fileVersion:ServerAPI.File.Version

        if v0Upload {
            var appMetaData: AppMetaData?
            if let appMetaDataContents = fileTracker.appMetaData {
                appMetaData = AppMetaData(contents: appMetaDataContents)
            }
                        
            let fileGroup = ServerAPI.File.Version.FileGroup(fileGroupUUID: objectTracker.fileGroupUUID, objectType: objectType.objectType)
            fileVersion = .v0(url: localURL, mimeType: fileDeclaration.mimeType, checkSum: checkSum, changeResolverName: fileDeclaration.changeResolverName, fileGroup: fileGroup, appMetaData: appMetaData)
        }
        else {
            fileVersion = .vN(url: localURL)
        }
        
        let serverAPIFile = ServerAPI.File(fileUUID: uuid.uuidString, sharingGroupUUID: objectEntry.sharingGroupUUID.uuidString, deviceUUID: configuration.deviceUUID.uuidString, uploadObjectTrackerId: objectTrackerId, version: fileVersion)
        
        if let error = api.uploadFile(file: serverAPIFile, uploadIndex: uploadIndex, uploadCount: uploadCount) {
            // Not going to throw an error here. Because this method is used in the context of a loop, and some of the uploads may have started correctly.
            delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.error(self, error: .error(error))
            }
        }
        else {
            try fileTracker.update(setters:
                UploadFileTracker.statusField.description <- .uploading)
        }
    }
}
