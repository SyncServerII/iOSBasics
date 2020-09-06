//
//  DeclaredObjectTests.swift
//  SyncServerTests
//
//  Created by Christopher G Prince on 9/3/20.
//

import XCTest
import ServerShared
@testable import iOSBasics

class DeclaredObjectTests: XCTestCase {
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    let url1 = URL(fileURLWithPath: "http://cprince.com")
    let url2 = URL(fileURLWithPath: "http://google.com")

    func testHasDistinctUUIDsWorks() {
        let fileUUID1 = UUID()
        let fileUUID2 = UUID()

        
        let upload1 = FileUpload(uuid: fileUUID1, dataSource: .copy(url1))
        let upload2 = FileUpload(uuid: fileUUID2, dataSource: .immutable(url1))
        let upload3 = FileUpload(uuid: fileUUID2, dataSource: .copy(url1))

        let uploads1 = Set<FileUpload>([upload1, upload2])
        XCTAssert(uploads1.count == 2)
        XCTAssert(FileUpload.hasDistinctUUIDs(in: uploads1))
        
        let uploads2 = Set<FileUpload>([upload2, upload3])
        XCTAssert(uploads2.count == 2)
        XCTAssert(!FileUpload.hasDistinctUUIDs(in: uploads2))
    }

    func testSingleFileDeclarationCompareWorks() throws {
        let declaration1 = FileDeclaration(uuid: UUID(), mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declaration2 = FileDeclaration(uuid: UUID(), mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        XCTAssert(declaration1.compare(to: declaration1))
        XCTAssertFalse(declaration1.compare(to: declaration2))
    }
    
    func testFileDeclarationSetCompareWorks() throws {
        let declaration1 = FileDeclaration(uuid: UUID(), mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declaration2 = FileDeclaration(uuid: UUID(), mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declarations1 = Set<FileDeclaration>(arrayLiteral: declaration1)
        let declarations2 = Set<FileDeclaration>()
        let declarations3 = Set<FileDeclaration>(arrayLiteral: declaration2)

        XCTAssertFalse(FileDeclaration.compare(first: declarations1, second: declarations2))
        XCTAssertFalse(FileDeclaration.compare(first: declarations1, second: declarations3))
        XCTAssert(FileDeclaration.compare(first: declarations1, second: declarations1))
    }
     
    func testSingleFileUploadCompareWorks() throws {
        let upload1 = FileUpload(uuid: UUID(), dataSource: .copy(url1))
        let upload2 = FileUpload(uuid: UUID(), dataSource: .copy(url1))
        XCTAssert(upload1.compare(to: upload1))
        XCTAssertFalse(upload1.compare(to: upload2))
    }
    
    func testFileUploadSetCompareWorks() throws {
        let upload1 = FileUpload(uuid: UUID(), dataSource: .copy(url1))
        let upload2 = FileUpload(uuid: UUID(), dataSource: .copy(url1))
        let uploads1 = Set<FileUpload>([upload1, upload2])
        let uploads2 = Set<FileUpload>([upload1])
        let uploads3 = Set<FileUpload>()
        
        XCTAssertFalse(FileUpload.compare(first: uploads1, second: uploads2))
        XCTAssert(FileUpload.compare(first: uploads1, second: uploads1))
        XCTAssertFalse(FileUpload.compare(first: uploads1, second: uploads3))
    }
    
    func testObjectDeclarationCompareWorks() {
        let declaration1 = FileDeclaration(uuid: UUID(), mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let declaration2 = FileDeclaration(uuid: UUID(), mimeType: MimeType.text, cloudStorageType: .Dropbox, appMetaData: nil, changeResolverName: nil)
        let objDecl1 = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: UUID(), declaredFiles: [declaration1, declaration2])
        let objDecl2 = ObjectDeclaration(fileGroupUUID: UUID(), objectType: "foo", sharingGroupUUID: UUID(), declaredFiles: [declaration1])
        
        XCTAssertFalse(objDecl1.compare(to: objDecl2))
        XCTAssert(objDecl1.compare(to: objDecl1))
    }
}
