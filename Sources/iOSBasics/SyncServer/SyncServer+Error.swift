
import Foundation

enum SyncServerError: Error {
    case declarationDifferentThanSyncedObject(String)
    case tooManyObjects
    case noObject
    case noObjectId
    case fileNotDeclared
    case uploadsDoNotHaveDistinctUUIDs
    case declaredFilesDoNotHaveDistinctUUIDs
    case noUploads
    case noDownloads
    case noDeclaredFiles
    case internalError(String)
    case attemptToQueueUploadOfVNAndV0Files
    case attemptToQueueADeletedFile
    case noObjectTypeForNewDeclaration
    case unknownSharingGroup
    case attemptToQueueAFileThatHasNotBeenDownloaded
    case attemptToDeleteObjectWithInvalidDeclaration
    case attemptToDeleteAnAlreadyDeletedFile
    case downloadingObjectAlreadyBeingDownloaded
    case downloadsDoNotHaveDistinctUUIDs
    
    static func ==(lhs: Self, rhs: Self) -> Bool {
        switch lhs {
        case declarationDifferentThanSyncedObject:
            guard case .declarationDifferentThanSyncedObject = rhs else {
                return false
            }
            return true
            
        case tooManyObjects:
            guard case .tooManyObjects = rhs else {
                return false
            }
            return true
            
        case noObject:
            guard case .noObject = rhs else {
                return false
            }
            return true
            
        case noObjectId:
            guard case .noObjectId = rhs else {
                return false
            }
            return true
            
        case fileNotDeclared:
            guard case .fileNotDeclared = rhs else {
                return false
            }
            return true
            
        case uploadsDoNotHaveDistinctUUIDs:
            guard case .uploadsDoNotHaveDistinctUUIDs = rhs else {
                return false
            }
            return true
            
        case declaredFilesDoNotHaveDistinctUUIDs:
            guard case .declaredFilesDoNotHaveDistinctUUIDs = rhs else {
                return false
            }
            return true
            
        case noUploads:
            guard case .noUploads = rhs else {
                return false
            }
            return true

        case noDownloads:
            guard case .noDownloads = rhs else {
                return false
            }
            return true

        case noDeclaredFiles:
            guard case .noDeclaredFiles = rhs else {
                return false
            }
            return true
            
        case internalError(let str1):
            guard case .internalError(let str2) = rhs, str1 == str2 else {
                return false
            }
            return true
            
        case attemptToQueueUploadOfVNAndV0Files:
            guard case .attemptToQueueUploadOfVNAndV0Files = rhs else {
                return false
            }
            return true
            
        case attemptToQueueADeletedFile:
            guard case .attemptToQueueADeletedFile = rhs else {
                return false
            }
            return true
            
        case noObjectTypeForNewDeclaration:
            guard case .noObjectTypeForNewDeclaration = rhs else {
                return false
            }
            return true
            
        case unknownSharingGroup:
            guard case .unknownSharingGroup = rhs else {
                return false
            }
            return true
            
        case attemptToQueueAFileThatHasNotBeenDownloaded:
            guard case .attemptToQueueAFileThatHasNotBeenDownloaded = rhs else {
                return false
            }
            return true

        case attemptToDeleteObjectWithInvalidDeclaration:
            guard case .attemptToDeleteObjectWithInvalidDeclaration = rhs else {
                return false
            }
            return true

        case attemptToDeleteAnAlreadyDeletedFile:
            guard case .attemptToDeleteAnAlreadyDeletedFile = rhs else {
                return false
            }
            return true

        case downloadingObjectAlreadyBeingDownloaded:
            guard case .downloadingObjectAlreadyBeingDownloaded = rhs else {
                return false
            }
            return true

        case downloadsDoNotHaveDistinctUUIDs:
            guard case .downloadsDoNotHaveDistinctUUIDs = rhs else {
                return false
            }
            return true
        }
    }
}

extension SyncServer {
    func reportError(_ error: Error) {
        delegator { [weak self] delegate in
            guard let self = self else { return }
            delegate.error(self, error: error)
        }
    }
}
