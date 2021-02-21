
import Foundation

public enum SyncServerError: Error {
    case declarationDifferentThanSyncedObject(String)
    case tooManyObjects
    case noObject
    case noObjectMatch
    case noObjectId
    case fileNotDeclared
    case objectNotDeclared
    case uploadsDoNotHaveDistinctUUIDs
    case declaredFilesDoNotHaveDistinctUUIDs
    case noUploads
    case noDownloads
    case noDeclaredFiles
    case internalError(String)
    case attemptToQueueUploadOfVNAndV0Files
    
    case attemptToQueueADeletedFile
    case attemptToDeleteObjectWithInvalidDeclaration
    case attemptToDeleteAnAlreadyDeletedFile
    case fileNotDeletedOnServer
    
    case noObjectTypeForNewDeclaration
    
    case attemptToQueueAFileThatHasNotBeenDownloaded
    case downloadingObjectAlreadyBeingDownloaded
    case downloadsDoNotHaveDistinctUUIDs
    case noMatchingUUID
    case matchingUUIDButNoFileLabel
    case fileNotDownloaded
    case badFileVersion
    
    case attemptToCreateExistingSharingGroup
    case sharingGroupNotFound
    case sharingGroupDeleted
    
    case noCloudStorageType
    
    case objectDoesNotHaveAllExistingFiles
    case duplicateFileLabel
    case someFileLabelsNotInDeclaredObject
    case badFileLabel
    
    case someUploadFilesV0SomeVN
    case noChangeResolver
    
    case noMimeTypes
    case matchingFileLabelButOtherDifferences
    case nilUploadMimeTypeButNotJustOneMimeTypeInDeclaration
    case attemptToUploadWithDifferentMimeType
    case mimeTypeNotInDeclaration
    
    case networkNotReachable
    
    static func ==(lhs: Self, rhs: Self) -> Bool {
        switch lhs {
         case networkNotReachable:
            guard case .networkNotReachable = rhs else {
                return false
            }
            return true
            
         case mimeTypeNotInDeclaration:
            guard case .mimeTypeNotInDeclaration = rhs else {
                return false
            }
            return true
            
         case attemptToUploadWithDifferentMimeType:
            guard case .attemptToUploadWithDifferentMimeType = rhs else {
                return false
            }
            return true
            
        case nilUploadMimeTypeButNotJustOneMimeTypeInDeclaration:
            guard case .nilUploadMimeTypeButNotJustOneMimeTypeInDeclaration = rhs else {
                return false
            }
            return true
            
        case matchingFileLabelButOtherDifferences:
            guard case .matchingFileLabelButOtherDifferences = rhs else {
                return false
            }
            return true
            
        case noMimeTypes:
            guard case .noMimeTypes = rhs else {
                return false
            }
            return true
            
        case badFileLabel:
            guard case .badFileLabel = rhs else {
                return false
            }
            return true
            
        case sharingGroupDeleted:
            guard case .sharingGroupDeleted = rhs else {
                return false
            }
            return true
            
        case noChangeResolver:
            guard case .noChangeResolver = rhs else {
                return false
            }
            return true
            
        case matchingUUIDButNoFileLabel:
            guard case .matchingUUIDButNoFileLabel = rhs else {
                return false
            }
            return true
            
        case noMatchingUUID:
            guard case .noMatchingUUID = rhs else {
                return false
            }
            return true
            
        case someUploadFilesV0SomeVN:
            guard case .someUploadFilesV0SomeVN = rhs else {
                return false
            }
            return true
            
        case someFileLabelsNotInDeclaredObject:
            guard case .someFileLabelsNotInDeclaredObject = rhs else {
                return false
            }
            return true
            
        case duplicateFileLabel:
            guard case .duplicateFileLabel = rhs else {
                return false
            }
            return true
            
        case objectDoesNotHaveAllExistingFiles:
            guard case .objectDoesNotHaveAllExistingFiles = rhs else {
                return false
            }
            return true
            
        case noCloudStorageType:
            guard case .noCloudStorageType = rhs else {
                return false
            }
            return true
            
        case sharingGroupNotFound:
            guard case .sharingGroupNotFound = rhs else {
                return false
            }
            return true
            
        case attemptToCreateExistingSharingGroup:
            guard case .attemptToCreateExistingSharingGroup = rhs else {
                return false
            }
            return true
            
        case badFileVersion:
            guard case .badFileVersion = rhs else {
                return false
            }
            return true
            
        case fileNotDownloaded:
            guard case .fileNotDownloaded = rhs else {
                return false
            }
            return true
        
        case fileNotDeletedOnServer:
            guard case .fileNotDeletedOnServer = rhs else {
                return false
            }
            return true
            
        case objectNotDeclared:
            guard case .objectNotDeclared = rhs else {
                return false
            }
            return true
            
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

        case noObjectMatch:
            guard case .noObjectMatch = rhs else {
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
            delegate.userEvent(self, event: .error(error))
        }
    }
}
