
import Foundation
@testable import iOSBasics

class ExampleDeclaration: DeclarableObject, ObjectDownloadHandler {
    func getFileLabel(appMetaData: String) -> String? {
        return appMetaDataMapping?[appMetaData]
    }
    
    func objectWasDownloaded(object: DownloadedObject) throws {
        self.objectWasDownloaded?(object)
    }
    
    let appMetaDataMapping: [String: String]?
    let declaredFiles: [DeclarableFile]
    let objectType: String
    let objectWasDownloaded:((DownloadedObject)->())?

    init(objectType: String, declaredFiles: [DeclarableFile], appMetaDataMapping: [String: String]? = nil, objectWasDownloaded:((DownloadedObject)->())? = nil) {
        self.objectType = objectType
        self.declaredFiles = declaredFiles
        self.appMetaDataMapping = appMetaDataMapping
        self.objectWasDownloaded = objectWasDownloaded
    }
}
