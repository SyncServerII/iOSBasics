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
    var syncCompleted: ((SyncServer, SyncResult) -> ())? { get set }
}

extension SyncServerTests where Self: XCTestCase {
    func uploadExampleTextFile(sharingGroupUUID: UUID) throws -> ObjectDeclaration {
        let fileUUID1 = UUID()
        
        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration1])

        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(exampleTextFileURL))
        let uploadables = Set<FileUpload>([uploadable1])

        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        try syncServer.queue(uploads: uploadables, declaration: testObject)
        
        waitForUploadsToComplete(numberUploads: 1)
        
        return testObject
    }
    
    func sync(withSharingGroupUUID sharingGroupUUID: UUID? = nil) throws {
        let exp = expectation(description: "exp")
        syncCompleted = { _, _ in
            exp.fulfill()
        }
        
        try syncServer.sync(sharingGroupUUID: sharingGroupUUID)
        waitForExpectations(timeout: 10, handler: nil)
    }
}

