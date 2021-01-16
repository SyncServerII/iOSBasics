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
    func syncToGetSharingGroupUUID() throws -> UUID {
        let exp = expectation(description: "exp")
        handlers.syncCompleted = { _, result in
            guard case .noIndex = result else {
                XCTFail()
                exp.fulfill()
                return
            }
            exp.fulfill()
        }

        try syncServer.sync()
        waitForExpectations(timeout: 10, handler: nil)
        handlers.syncCompleted = nil

        let groups = try syncServer.sharingGroups()

        guard groups.count > 0 else {
            throw SyncServerError.internalError("Testing Error")
        }

        return groups[0].sharingGroupUUID
    }

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

    func compare(uploadedFile: URL, downloadObject: DownloadedObject, to uploadObject: ObjectUpload, downloadHandlerCalled: inout Bool) throws {
        let localFileData = try Data(contentsOf: uploadedFile)

        guard downloadObject.downloads.count == 1 else {
            XCTFail()
            return
        }
        
        let downloadFile = downloadObject.downloads[0]
        XCTAssert(downloadObject.fileGroupUUID == uploadObject.fileGroupUUID)
        XCTAssert(uploadObject.uploads[0].fileLabel == downloadFile.fileLabel)
        XCTAssert(uploadObject.uploads[0].uuid == downloadFile.uuid)
        XCTAssert(downloadFile.fileVersion == 0)
        
        switch downloadFile.contents {
        case .gone:
            XCTFail()
        case .download(let url):
            let downloadedData = try Data(contentsOf: url)
            XCTAssert(localFileData == downloadedData)
        }
        
        downloadHandlerCalled = true
    }
    
    func uploadExampleTextFile(objectType: String = "Foo", sharingGroupUUID: UUID, localFile: URL = Self.exampleTextFileURL, objectWasDownloaded:((DownloadedObject)->())? = nil) throws -> (ObjectUpload, ExampleDeclaration) {
        let fileUUID1 = UUID()
        
        let fileDeclaration1 = FileDeclaration(fileLabel: "file1", mimeTypes: [.text], changeResolverName: nil)
        let example = ExampleDeclaration(objectType: objectType, declaredFiles: [fileDeclaration1], objectWasDownloaded: objectWasDownloaded)
        try syncServer.register(object: example)
                
        let fileUpload1 = FileUpload(fileLabel: fileDeclaration1.fileLabel, mimeType: .text, dataSource: .copy(localFile), uuid: fileUUID1)
        let upload = ObjectUpload(objectType: objectType, fileGroupUUID: UUID(), sharingGroupUUID: sharingGroupUUID, uploads: [fileUpload1])
        
        try syncServer.queue(upload: upload)
                
        waitForUploadsToComplete(numberUploads: 1)
        
        return (upload, example)
    }
    
    // Deletion complete with waiting for deferred part of the deletion.
    func delete(object fileGroupUUID: UUID) throws {
        let exp = expectation(description: "exp")
        handlers.deletionCompleted = { _, fgUUID in
            XCTAssert(fileGroupUUID == fgUUID)
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

