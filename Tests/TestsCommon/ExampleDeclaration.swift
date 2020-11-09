
import Foundation
@testable import iOSBasics

class ExampleDeclaration: DeclarableObject, ObjectDownloadHandler {
    func getFileLabel(appMetaData: String) -> String? {
        assert(false)
        return nil
    }
    
    func objectWasDownloaded(object: DownloadObject) {
    }
    
    let declaredFiles: [DeclarableFile]
    let objectType: String
    
    init(objectType: String, declaredFiles: [DeclarableFile]) {
        self.objectType = objectType
        self.declaredFiles = declaredFiles
    }
}
