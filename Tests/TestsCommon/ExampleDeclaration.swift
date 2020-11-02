
import Foundation
@testable import iOSBasics

class ExampleDeclaration: DeclarableObject, ObjectDownloadHandler {
    func getFileLabel(appMetaData: String) throws -> String {
        assert(false)
        return ""
    }
    
    func objectWasDownloaded(object: DeclarableObject) {
    }
    
    func getObjectType(appMetaData: String) throws -> String {
        return ""
    }
    
    let declaredFiles: [DeclarableFile]
    let objectType: String
    
    init(objectType: String, declaredFiles: [DeclarableFile]) {
        self.objectType = objectType
        self.declaredFiles = declaredFiles
    }
}
