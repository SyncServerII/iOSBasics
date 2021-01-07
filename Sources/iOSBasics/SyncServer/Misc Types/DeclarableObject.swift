import Foundation
import ServerShared

public protocol DeclarableFile {
    // Needed to indicate a specific file and because `mimeType`'s need not be unique across all files for an object. `fileLabel`'s must all be unique for a specific object.
    var fileLabel: String {get}
    
    // The possible mime types for this file.
    var mimeTypes: Set<MimeType> {get}

    // If the file will be changed and have multiple versions on the server, this must be non-nil and a valid change resolver name. For a static file that will not be changed beyond v0 of the file on the server, this must be nil.
    var changeResolverName: String? {get}
}

extension DeclarableFile {
    public func equal(_ other: DeclarableFile) -> Bool {
        return mimeTypes == other.mimeTypes
            && changeResolverName == other.changeResolverName
            && fileLabel == other.fileLabel
    }
}

public func equal(_ lhs: [DeclarableFile], _ rhs: [DeclarableFile]) -> Bool {
    guard lhs.count == rhs.count else {
        return false
    }
    
    for (index, lhsFile) in lhs.enumerated() {
        let rhsFile = rhs[index]
        guard lhsFile.equal(rhsFile) else {
            return false
        }
    }
    
    return true
}

public protocol DeclarableObjectBasics {
    // The type of object that this collection of files is representing.
    // E.g., a Neebla image or Neebla URL.
    var objectType: String { get }
}

/* An abstraction of a declaration of a data object backed by one or more cloud storage files. Two examples from Neebla:

1) An image object: Represented by a (a) jpg image file and (b) a discussion thread file.
2) A website object: Represented by (a) an optional jpg file for an image depicting the URL website contents, (b) a file containing the URL for the website, and (c) a discussion thread file.

Representations in terms of a set of files are selected both in terms of the need for storing information for an application's data object, and in terms of having representations that are basically intelligible to a user when stored in their cloud storage. For example, it wouldn't be suitable to compress data files in a non-obvious encoding. JPEG format is fine as it's widely used, and zip compression could be fine as well. But a proprietary compression algorithm not widely used would not be suitable.
*/
public protocol DeclarableObject: DeclarableObjectBasics {
    // This is an array (and not a set) because it is allowable to have multiple files in a declaration with the same mimeType and changeResolver. And because sets introduce associated types into Swift protocols and that's just annoying! :).
    var declaredFiles: [DeclarableFile] { get }
}

extension DeclarableObject {
    public func equal(_ other: DeclarableObject) -> Bool {
        return objectType == other.objectType
            && iOSBasics.equal(declaredFiles, other.declaredFiles)
    }
}
