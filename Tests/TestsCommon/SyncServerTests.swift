//
//  File.swift
//  
//
//  Created by Christopher G Prince on 9/12/20.
//

import XCTest
import iOSBasics
import ServerShared

protocol SyncServerTests: TestFiles, APITests {
    var syncServer:SyncServer! { get }
}

extension SyncServerTests where Self: XCTestCase {
    func uploadExampleTextFile(sharingGroupUUID: UUID) throws -> ObjectDeclaration {
        let fileUUID1 = UUID()
        
        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration1])

        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable1])

        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        try syncServer.queue(declaration: testObject, uploads: uploadables)
        
        waitForUploadsToComplete(numberUploads: 1)
        
        return testObject
    }
}

