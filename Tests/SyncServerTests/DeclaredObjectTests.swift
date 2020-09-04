//
//  DeclaredObjectTests.swift
//  SyncServerTests
//
//  Created by Christopher G Prince on 9/3/20.
//

import XCTest
import ServerShared
import iOSBasics

class DeclaredObjectTests: XCTestCase {
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testSingleFileDeclarationCompareWorks() throws {
        let declaration1 = FileDeclaration(uuid: UUID(), mimeType: MimeType.text, appMetaData: nil, changeResolverName: nil)
        let declaration2 = FileDeclaration(uuid: UUID(), mimeType: MimeType.text, appMetaData: nil, changeResolverName: nil)
        XCTAssert(declaration1.compare(to: declaration1))
        XCTAssertFalse(declaration1.compare(to: declaration2))
    }
    
    func testFileDeclarationSetCompareWorks() throws {
        let declaration1 = FileDeclaration(uuid: UUID(), mimeType: MimeType.text, appMetaData: nil, changeResolverName: nil)
        let declaration2 = FileDeclaration(uuid: UUID(), mimeType: MimeType.text, appMetaData: nil, changeResolverName: nil)
        let declarations1 = Set<FileDeclaration>(arrayLiteral: declaration1)
        let declarations2 = Set<FileDeclaration>()
        let declarations3 = Set<FileDeclaration>(arrayLiteral: declaration2)

        XCTAssertFalse(FileDeclaration.compare(first: declarations1, second: declarations2))
        XCTAssertFalse(FileDeclaration.compare(first: declarations1, second: declarations3))
        XCTAssert(FileDeclaration.compare(first: declarations1, second: declarations1))
    }
 
    func testSingleFileUploadCompareWorks() throws {
    }
}
