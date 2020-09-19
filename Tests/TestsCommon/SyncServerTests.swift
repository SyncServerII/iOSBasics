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
    var handlers: DelegateHandlers { get }
}

extension SyncServerTests where Self: XCTestCase {
    func uploadExampleTextFile(sharingGroupUUID: UUID, localFile: URL = Self.exampleTextFileURL) throws -> ObjectDeclaration {
        let fileUUID1 = UUID()
        
        let declaration1 = FileDeclaration(uuid: fileUUID1, mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations = Set<FileDeclaration>([declaration1])

        let uploadable1 = FileUpload(uuid: fileUUID1, dataSource: .copy(localFile))
        let uploadables = Set<FileUpload>([uploadable1])

        let testObject = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: sharingGroupUUID, declaredFiles: declarations)
        
        try syncServer.queue(uploads: uploadables, declaration: testObject)
        
        waitForUploadsToComplete(numberUploads: 1)
        
        return testObject
    }
    
    func sync(withSharingGroupUUID sharingGroupUUID: UUID? = nil) throws {
        let exp = expectation(description: "exp")
        handlers.syncCompleted = { _, _ in
            exp.fulfill()
        }
        
        try syncServer.sync(sharingGroupUUID: sharingGroupUUID)
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    // Deletion complete with waiting for deferred part of the deletion.
    func delete<DECL: DeclarableObject>(object: DECL) throws {
        let exp = expectation(description: "exp")
        handlers.deletionCompleted = { _ in
            exp.fulfill()
        }
        
        try syncServer.delete(object: object)
        waitForExpectations(timeout: 10, handler: nil)
        
        // Wait for some period of time for the deferred deletion to complete.
        Thread.sleep(forTimeInterval: 5)

        // This `sync` is to trigger the check for the deferred upload completion.
        try syncServer.sync()

        let exp2 = expectation(description: "exp2")
        handlers.deferredCompleted = { _, operation, count in
            XCTAssert(operation == .deletion)
            XCTAssert(count == 1)
            exp2.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
    }
}

