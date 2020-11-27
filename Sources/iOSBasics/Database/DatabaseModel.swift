import Foundation

enum DatabaseError: Error {
    case noObject
    case noObjectType
    case notExactlyOneWithFileLabel
    case tooManyObjects
    case declarationDifferentThanModel
    case notExactlyOneRow
    case invalidUUID
    case invalidSharingGroupUUID
    case badMimeType
    case badCloudStorageType
    case noFileDeclarations
    case problemWithOtherMatchingAttributes
    case notMatching
    case noFileLabel
    case invalidCreationDate
}
