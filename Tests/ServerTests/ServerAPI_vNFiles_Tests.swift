//
//  ServerAPI_vNFiles_Tests.swift
//  iOSBasicsTests
//
//  Created by Christopher G Prince on 8/23/20.
//

import XCTest
@testable import iOSBasics
import iOSSignIn
import ServerShared
import iOSShared
import iOSDropbox
import SQLite
import ChangeResolvers

public struct ExampleComment {
    static let messageKey = "messageString"
    public let messageString:String
    public let id: String
    
    public var record:CommentFile.FixedObject {
        var result = CommentFile.FixedObject()
        result[CommentFile.idKey] = id
        result[Self.messageKey] = messageString
        return result
    }
    
    public var updateContents: Data {
        return try! JSONSerialization.data(withJSONObject: record)
    }
}

class ServerAPI_vNFiles_Tests: XCTestCase, APITests, Dropbox, ServerBasics {
    var credentials: GenericCredentials!
    var api:ServerAPI!
    let deviceUUID = UUID()
    var database: Connection!
    let hashingManager = HashingManager()
    let dropboxHashing = DropboxHashing()
    let config = Networking.Configuration(temporaryFileDirectory: Files.getDocumentsDirectory(), temporaryFilePrefix: "SyncServer", temporaryFileExtension: "dat", baseURL: baseURL(), minimumServerVersion: nil, packageTests: true)
    var uploadCompletedHandler: ((_ result: Swift.Result<UploadFileResult, Error>) -> ())?
    var downloadCompletedHandler: ((_ result: Swift.Result<DownloadFileResult, Error>) -> ())?
    
    override func setUpWithError() throws {
        database = try Connection(.inMemory)
        try hashingManager.add(hashing: dropboxHashing)
        credentials = try setupDropboxCredentials()
        api = ServerAPI(database: database, hashingManager: hashingManager, delegate: self, config: config)
        uploadCompletedHandler = nil
        try NetworkCache.createTable(db: database)
    }

    func fileUpload() throws {
        // Get ready for test.
        removeDropboxUser()
        guard addDropboxUser() else {
            XCTFail()
            return
        }
        
        let fileUUID = UUID()
        
        let commentFileString = "{\"elements\":[]}"
        let commentFileData = commentFileString.data(using: .utf8)!
        let dropboxCheckSum =  "3ffce28e9fc6181b1e52226cba61dbdbd13fc1b75decb770f075541b25010575"
                
        guard let result = getIndex(sharingGroupUUID: nil),
            result.sharingGroups.count > 0,
            let sharingGroupUUID = result.sharingGroups[0].sharingGroupUUID else {
            XCTFail()
            return
        }
        
        let changeResolverName = CommentFile.changeResolverName

        let file1 = ServerAPI.File(fileUUID: fileUUID.uuidString, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID.uuidString, version:
            .v0(source: .data(commentFileData), mimeType: MimeType.text, checkSum: dropboxCheckSum, changeResolverName: changeResolverName, fileGroupUUID: nil, appMetaData: nil)
        )
        
        guard let uploadResult1 = uploadFile(file: file1, uploadIndex: 1, uploadCount: 1) else {
            XCTFail()
            return
        }
        
        switch uploadResult1 {
        case .success:
            break
        default:
            XCTFail("\(uploadResult1)")
            return
        }
        
        let comment1 = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)

        let file2 = ServerAPI.File(fileUUID: fileUUID.uuidString, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID.uuidString, version:
            .vN(change: comment1.updateContents)
        )
        
        guard let uploadResult2 = uploadFile(file: file2, uploadIndex: 1, uploadCount: 1) else {
            XCTFail()
            return
        }
        
        var deferredUploadId: Int64!
        
        switch uploadResult2 {
        case .success(let result):
            guard case .success(creationDate: _, updateDate: _, deferredUploadId: let id) = result, let deferredId = id else {
                XCTFail()
                return
            }
            deferredUploadId = deferredId
            
        default:
            XCTFail("\(uploadResult2)")
        }
        
        if let deferredUploadId = deferredUploadId {
            // Wait for a bit, before polling server to see if the upload is done.
            let exp = expectation(description: "Deferred Upload")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                exp.fulfill()
            }
            waitForExpectations(timeout: 10, handler: nil)
            
            var status: DeferredUploadStatus?
            let getUploadsResult = self.getUploadsResults(deferredUploadId: deferredUploadId)
            if case .success(let s) = getUploadsResult {
                status = s
            }
            
            XCTAssert(status == .completed, "\(String(describing: status))")
        }
        
        XCTAssert(removeDropboxUser())
    }
    
    func testVNFileUploadWorks() throws {
        try fileUpload()
    }
}
