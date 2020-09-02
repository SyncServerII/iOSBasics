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

class ServerAPI_vNFiles_Tests: APITestCase, APITests {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try user = dropboxUser()
        uploadCompletedHandler = nil
        try NetworkCache.createTable(db: database)
        _ = user.removeUser()
        XCTAssert(user.addUser())
    }

    @discardableResult
    func fileUpload(comment:ExampleComment) throws -> ServerAPI.File? {        
        let fileUUID = UUID()
        
        let commentFileString = "{\"elements\":[]}"
        let commentFileData = commentFileString.data(using: .utf8)!
        let dropboxCheckSum =  "3ffce28e9fc6181b1e52226cba61dbdbd13fc1b75decb770f075541b25010575"
                
        guard let result = getIndex(sharingGroupUUID: nil),
            result.sharingGroups.count > 0,
            let sharingGroupUUID = result.sharingGroups[0].sharingGroupUUID else {
            XCTFail()
            return nil
        }
        
        let changeResolverName = CommentFile.changeResolverName

        let file1 = ServerAPI.File(fileUUID: fileUUID.uuidString, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID.uuidString, version:
            .v0(source: .data(commentFileData), mimeType: MimeType.text, checkSum: dropboxCheckSum, changeResolverName: changeResolverName, fileGroupUUID: nil, appMetaData: nil)
        )
        
        guard let uploadResult1 = uploadFile(file: file1, uploadIndex: 1, uploadCount: 1) else {
            XCTFail()
            return nil
        }
        
        switch uploadResult1 {
        case .success:
            break
        default:
            XCTFail("\(uploadResult1)")
            return nil
        }
        
        let file2 = ServerAPI.File(fileUUID: fileUUID.uuidString, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID.uuidString, version:
            .vN(change: comment.updateContents)
        )
        
        guard let uploadResult2 = uploadFile(file: file2, uploadIndex: 1, uploadCount: 1) else {
            XCTFail()
            return nil
        }
        
        var deferredUploadId: Int64!
        
        switch uploadResult2 {
        case .success(let result):
            guard case .success(creationDate: _, updateDate: _, deferredUploadId: let id) = result, let deferredId = id else {
                XCTFail()
                return nil
            }
            deferredUploadId = deferredId
            
        default:
            XCTFail("\(uploadResult2)")
        }
        
        if let deferredUploadId = deferredUploadId {            
            let status = delayedGetUploadsResults(deferredUploadId: deferredUploadId)
            XCTAssert(status == .completed, "\(String(describing: status))")
        }
        
        return file1
    }
    
    func testVNFileUploadWorks() throws {
        let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        try fileUpload(comment: comment)
    }
    
    func testVNFileDownloadWorks() throws {
        let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        guard let file = try fileUpload(comment: comment) else {
            XCTFail()
            return
        }
        
        guard let download = downloadFile(fileUUID: file.fileUUID, fileVersion: 1, sharingGroupUUID: file.sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let downloadResult:DownloadFileResult
        switch download {
        case .success(let result):
            downloadResult = result
        default:
            XCTFail()
            return
        }
        
        let downloadedURL: URL
        switch downloadResult {
        case .success(url: let url, appMetaData: _, checkSum: _, cloudStorageType: _, contentsChangedOnServer: _):
            downloadedURL = url
        default:
            XCTFail()
            return
        }
        
        let downloadedData = try Data(contentsOf: downloadedURL)
        let downloadedCommentFile = try CommentFile(with: downloadedData)
        
        guard downloadedCommentFile.count == 1 else {
            XCTFail()
            return
        }
        
        let downloadedDict = downloadedCommentFile[0]
        XCTAssert((downloadedDict?[CommentFile.idKey] as? String) == comment.id)
        XCTAssert((downloadedDict?[ExampleComment.messageKey] as? String) == comment.messageString)
    }
}
