//
//  File.swift
//  
//
//  Created by Christopher G Prince on 9/12/20.
//

import XCTest
@testable import iOSBasics
import ServerShared
import iOSShared

protocol SyncServerTests: TestFiles, APITests {
    var syncServer:SyncServer! { get }
    var handlers: DelegateHandlers { get }
}

extension SyncServerTests where Self: XCTestCase {
    func sync(withSharingGroupUUID sharingGroupUUID: UUID? = nil) throws {
        let exp = expectation(description: "exp")
        handlers.syncCompleted = { _, result in
            switch result {
            case .index(sharingGroupUUID: _, index: _):
                XCTAssert(sharingGroupUUID != nil)
            case .noIndex:
                XCTAssert(sharingGroupUUID == nil)
            }
            exp.fulfill()
        }
        
        try syncServer.sync(sharingGroupUUID: sharingGroupUUID)
        waitForExpectations(timeout: 10, handler: nil)
        
        handlers.syncCompleted = nil
    }

    func uploadExampleTextFile(sharingGroupUUID: UUID, localFile: URL = Self.exampleTextFileURL) throws -> (ObjectUpload, ExampleDeclaration) {
        let fileUUID1 = UUID()
        
        let objectType = "Foo"
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeType: .text, changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1])
        try syncServer.register(object: example)
        
        let fileUpload1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, dataSource: .copy(localFile), uuid: fileUUID1)
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload1])
        
        try syncServer.queue(upload: upload)
                
        waitForUploadsToComplete(numberUploads: 1)
        
        return (upload, example)
    }
    
    // Deletion complete with waiting for deferred part of the deletion.
    func delete(object fileGroupUUID: UUID) throws {
        let exp = expectation(description: "exp")
        handlers.deletionCompleted = { _ in
            logger.debug("delete: handlers.deletionCompleted")
            exp.fulfill()
        }
        
        try syncServer.queue(objectDeletion: fileGroupUUID)
        waitForExpectations(timeout: 10, handler: nil)
        logger.debug("delete: Done queue deletion")
        
        // Wait for some period of time for the deferred deletion to complete.
        Thread.sleep(forTimeInterval: 5)

        let exp2 = expectation(description: "exp2")
        handlers.syncCompleted = { _, _ in
            exp2.fulfill()
        }
        
        // This `sync` is to trigger the check for the deferred upload completion.
        try syncServer.sync()
        logger.debug("delete: Done sync")
        
        let exp3 = expectation(description: "exp2")
        handlers.deferredCompleted = { _, operation, count in
            logger.debug("delete: handlers.deferredCompleted")
            XCTAssert(operation == .deletion)
            XCTAssert(count == 1)
            exp3.fulfill()
        }
        waitForExpectations(timeout: 10, handler: nil)
    }
}

