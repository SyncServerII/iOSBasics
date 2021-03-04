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
@testable import TestsCommon

class ServerAPI_vNFiles_Tests: XCTestCase, UserSetup, APITests, ServerAPIDelegator, ServerBasics {
    var hashingManager: HashingManager!
    var api: ServerAPI!
    var handlers = DelegateHandlers()
    var deviceUUID: UUID!
    var database: Connection!
    let config = Configuration.defaultTemporaryFiles

    override func setUpWithError() throws {
        try super.setUpWithError()
        handlers = DelegateHandlers()
        handlers.user = try dropboxUser()
        deviceUUID = UUID()
        let database = try Connection(.inMemory)
        try NetworkCache.createTable(db: database)
        let config = Configuration(appGroupIdentifier: nil, serverURL: URL(string: Self.baseURL())!, minimumServerVersion: nil, failoverMessageURL: nil, cloudFolderName: cloudFolderName, deviceUUID: deviceUUID, packageTests: true)
        hashingManager = HashingManager()
        try? hashingManager.add(hashing: DropboxHashing())
        let serialQueue = DispatchQueue(label: "iOSBasicsTests")
        api = ServerAPI(database: database, hashingManager: hashingManager, reachability: FakeReachability(), delegate: self, serialQueue: serialQueue, config: config)
        _ = handlers.user.removeUser()
        XCTAssert(handlers.user.addUser())
    }
    
    // 11/28/20; Uploads a file with a nil file group.
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
        
        let commentDataURL1 = try FileUtils.copyDataToNewTemporary(data: commentFileData, config: config)

        let file1 = ServerAPI.File(fileUUID: fileUUID.uuidString, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID.uuidString, uploadObjectTrackerId: -1, batchUUID: UUID(), batchExpiryInterval: 100, version:
            .v0(url: commentDataURL1, mimeType: MimeType.text, checkSum: dropboxCheckSum, changeResolverName: changeResolverName, fileGroup: nil, appMetaData: nil, fileLabel: UUID().uuidString)
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
        
        let commentDataURL2 = try FileUtils.copyDataToNewTemporary(data: comment.updateContents, config: config)
        
        let file2 = ServerAPI.File(fileUUID: fileUUID.uuidString, sharingGroupUUID: sharingGroupUUID, deviceUUID: deviceUUID.uuidString, uploadObjectTrackerId: -1, batchUUID: UUID(), batchExpiryInterval: 100, version:
            .vN(url: commentDataURL2)
        )
        
        guard let uploadResult2 = uploadFile(file: file2, uploadIndex: 1, uploadCount: 1) else {
            XCTFail()
            return nil
        }
        
        var deferredUploadId: Int64!
        
        switch uploadResult2 {
        case .success(let result):
            guard case .success(let uploadResult) = result,
                let deferredId = uploadResult.deferredUploadId else {
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
        // 11/28/20; Uploads a file with a nil file group.
        try fileUpload(comment: comment)
    }
    
    func testVNFileDownloadWorks() throws {
        let comment = ExampleComment(messageString: "Example", id: Foundation.UUID().uuidString)
        // 11/28/20; Uploads a file with a nil file group.
        guard let file = try fileUpload(comment: comment) else {
            XCTFail()
            return
        }
        
        guard let download = downloadFile(fileUUID: file.fileUUID, fileVersion: 1, downloadObjectTrackerId: -1, sharingGroupUUID: file.sharingGroupUUID) else {
            XCTFail()
            return
        }
        
        let downloadResult:DownloadFileResult
        switch download {
        case .success(let result):
            downloadResult = result
        default:
            XCTFail("\(download)")
            return
        }
        
        let downloadedURL: URL
        switch downloadResult {
        case .success(_, let result):
            downloadedURL = result.url
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
