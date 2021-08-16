//
//  SyncServer+SingleUpload.swift
//  
//
//  Created by Christopher G Prince on 9/6/20.
//

import Foundation
import ServerShared
import SQLite
import iOSShared

extension SyncServer {
    // Assumes that an UploadFileTracker has already been created for the file referenced by fileUUID.
    func singleUpload(objectType: DeclaredObjectModel, objectTracker: UploadObjectTracker, objectEntry: DirectoryObjectEntry, fileLabel: String, fileUUID: UUID) throws {

        guard let objectTrackerId = objectTracker.id else {
            throw SyncServerError.internalError("Could not get object tracker id")
        }
            
        guard let fileTracker = try UploadFileTracker.fetchSingleRow(db: db, where:
            fileUUID == UploadFileTracker.fileUUIDField.description &&
            objectTrackerId == UploadFileTracker.uploadObjectTrackerIdField.description) else {
            throw SyncServerError.internalError("Could not get upload file tracker: \(fileUUID)")
        }

        try uploadSingle(objectType: objectType, objectTracker: objectTracker, objectEntry: objectEntry, fileTracker: fileTracker, fileLabel: fileLabel)
    }
    
    // Start a single file uploading.
    func uploadSingle(objectType: DeclaredObjectModel, objectTracker: UploadObjectTracker, objectEntry: DirectoryObjectEntry, fileTracker: UploadFileTracker, fileLabel: String) throws {
        let fileVersion:ServerAPI.File.Version

        guard configuration.allowUploadDownload else {
            logger.warning("allowUploadDownload is false; not doing upload.")
            return
        }
        
        guard let checkSum = fileTracker.checkSum,
            let localURL = fileTracker.localURL else {
            throw SyncServerError.internalError("Could not get checkSum or localURL")
        }

        let fileDeclaration = try objectType.getFile(with: fileLabel)

        guard let objectTrackerId = objectTracker.id,
            let v0Upload = objectTracker.v0Upload else {
            throw SyncServerError.internalError("Could not get object tracker id or v0Upload")
        }
        
        if v0Upload {
            var appMetaData: AppMetaData?
            if let appMetaDataContents = fileTracker.appMetaData {
                appMetaData = AppMetaData(contents: appMetaDataContents)
            }
                        
            let fileGroup = ServerAPI.File.Version.FileGroup(fileGroupUUID: objectTracker.fileGroupUUID, objectType: objectType.objectType)
            fileVersion = .v0(url: localURL, mimeType: fileTracker.mimeType, checkSum: checkSum, changeResolverName: fileDeclaration.changeResolverName, fileGroup: fileGroup, appMetaData: appMetaData, fileLabel: fileDeclaration.fileLabel)
        }
        else {
            fileVersion = .vN(url: localURL)
        }
        
        let serverAPIFile = ServerAPI.File(fileTracker: fileTracker, fileUUID: fileTracker.fileUUID.uuidString, sharingGroupUUID: objectEntry.sharingGroupUUID.uuidString, deviceUUID: configuration.deviceUUID.uuidString, uploadObjectTrackerId: objectTrackerId, batchUUID: objectTracker.batchUUID, batchExpiryInterval: objectTracker.batchExpiryInterval, version: fileVersion, informAllButSelf: fileTracker.informAllButSelf)
        
        if let error = api.uploadFile(file: serverAPIFile, uploadIndex: fileTracker.uploadIndex, uploadCount: fileTracker.uploadCount) {
            delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.userEvent(self, event: .error(error))
            }
        }
        else {
            let expiry = try UploadFileTracker.expiryDate(expiryDuration: configuration.expiryDuration)
            try fileTracker.update(setters:
                UploadFileTracker.statusField.description <- .uploading,
                UploadFileTracker.expiryField.description <- expiry)
            if !v0Upload {
                // vNUpload, so we'll start to poll for completion of deferred uploads.
                startTimedDeferredCheckIfNeeded()
            }
        }
    }
}
