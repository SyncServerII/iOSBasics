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
    // uploadIndex >= 1 and uploadIndex <= uploadCount
    func singleUpload<DECL: DeclarableObject>(declaration: DECL, fileUUID uuid: UUID, v0Upload: Bool, objectTrackerId: Int64, uploadIndex: Int32, uploadCount: Int32) throws {
        let declaredFile = try fileDeclaration(for: uuid, declaration: declaration)
        
        guard let uploadFileTracker = try UploadFileTracker.fetchSingleRow(db: db, where:
            uuid == UploadFileTracker.fileUUIDField.description &&
            objectTrackerId == UploadFileTracker.uploadObjectTrackerIdField.description),
            let checkSum = uploadFileTracker.checkSum,
            let localURL = uploadFileTracker.localURL else {
            throw SyncServerError.internalError("Could not get upload file tracker: \(uuid)")
        }
        
        let uploadObjectTrackerId = uploadFileTracker.uploadObjectTrackerId
        let fileVersion:ServerAPI.File.Version
        
        if v0Upload {
            var appMetaData: AppMetaData?
            if let appMetaDataContents = declaredFile.appMetaData {
                appMetaData = AppMetaData(contents: appMetaDataContents)
            }
            
            fileVersion = .v0(url: localURL, mimeType: declaredFile.mimeType, checkSum: checkSum, changeResolverName: declaredFile.changeResolverName, fileGroupUUID: declaration.fileGroupUUID.uuidString, appMetaData: appMetaData)
        }
        else {
            fileVersion = .vN(url: localURL)
        }
        
        let serverAPIFile = ServerAPI.File(fileUUID: uuid.uuidString, sharingGroupUUID: declaration.sharingGroupUUID.uuidString, deviceUUID: configuration.deviceUUID.uuidString, uploadObjectTrackerId: uploadObjectTrackerId, version: fileVersion)
        
        if let error = api.uploadFile(file: serverAPIFile, uploadIndex: uploadIndex, uploadCount: uploadCount) {
            throw SyncServerError.internalError("\(error)")
        }

        try uploadFileTracker.update(setters:
            UploadFileTracker.statusField.description <- .uploading)
    }
}
