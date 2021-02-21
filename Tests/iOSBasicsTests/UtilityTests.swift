//
//  UtilityTests.swift
//  iOSBasicsTests
//
//  Created by Christopher G Prince on 9/5/20.
//

import XCTest
@testable import iOSBasics
import iOSShared
@testable import TestsCommon

class UtilityTests: XCTestCase, TestFiles {
    override func setUpWithError() throws {
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testCopyFileToNewTemporary() throws {
        let config = Configuration.defaultTemporaryFiles
        let copy = try FileUtils.copyFileToNewTemporary(original: exampleTextFileURL, config: config)
        
        let originalData = try Data(contentsOf: exampleTextFileURL)
        let newData = try Data(contentsOf: copy)
        XCTAssert(originalData == newData)
    }
    
    func testCopyDataToNewTemporary() throws {
        let config = Configuration.defaultTemporaryFiles
        let originalData = "Hello, There!".data(using: .utf8)!
        let url = try FileUtils.copyDataToNewTemporary(data: originalData, config: config)
        let newData = try Data(contentsOf: url)
        XCTAssert(originalData == newData)
    }
}
