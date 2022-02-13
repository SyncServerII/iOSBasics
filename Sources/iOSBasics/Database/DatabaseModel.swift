import Foundation

enum DatabaseError: Error, Equatable {
    case noObject
    case noObjectType
    case notExactlyOneWithFileLabel
    case tooManyObjects
    case declarationDifferentThanModel
    case notExactlyOneRow(message: String)
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
