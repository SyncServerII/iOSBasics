//
//  SharingEntryTests.swift
//  iOSBasicsTests
//
//  Created by Christopher G Prince on 5/21/20.
//

import XCTest
@testable import iOSBasics
import SQLite
import ServerShared
// @testable import TestsCommon

class SharingEntryTests: XCTestCase {
    var database: Connection!
    let uuid = UUID()
    var entry:SharingEntry!
    
    override func setUpWithError() throws {
        database = try Connection(.inMemory)
        entry = try SharingEntry(db: database, permission: .admin, removedFromGroup: true, sharingGroupName: nil, sharingGroupUUID: uuid, syncNeeded: false, cloudStorageType: .Dropbox)
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func assertContentsCorrect(entry1: SharingEntry, entry2: SharingEntry) {
        XCTAssert(entry1.sharingGroupUUID == entry2.sharingGroupUUID)
        XCTAssert(entry1.permission == entry2.permission)
        XCTAssert(entry1.removedFromGroup == entry2.removedFromGroup)
        XCTAssert(entry1.sharingGroupName == entry2.sharingGroupName)
        XCTAssert(entry1.syncNeeded == entry2.syncNeeded)
        XCTAssert(entry1.cloudStorageType == entry2.cloudStorageType)
    }

    func testCreateTable() throws {
        try SharingEntry.createTable(db: database)
    }
    
    func testDoubleCreateTable() throws {
        try SharingEntry.createTable(db: database)
        try SharingEntry.createTable(db: database)
    }
    
    func testInsertIntoTable() throws {
        try SharingEntry.createTable(db: database)
        try entry.insert()
    }
    
    func testFilterWhenRowNotFound() throws {
        try SharingEntry.createTable(db: database)

        var count = 0
        try SharingEntry.fetch(db: database,
            where: uuid == SharingEntry.sharingGroupUUIDField.description) { row in
            count += 1
        }
        
        XCTAssert(count == 0)
    }
    
    func testFilterWhenRowFound() throws {
        try SharingEntry.createTable(db: database)
        try entry.insert()
        
        var count = 0
        try SharingEntry.fetch(db: database,
            where: uuid == SharingEntry.sharingGroupUUIDField.description) { row in
            assertContentsCorrect(entry1: entry, entry2: row)
            count += 1
        }
        
        XCTAssert(count == 1)
    }
    
    func testFilterWhenTwoRowsFound() throws {
        try SharingEntry.createTable(db: database)
        try entry.insert()
        
        // Second entry-- to have a different fileUUID, the primary key.
        let entry2 = try SharingEntry(db: database, permission: .admin, removedFromGroup: true, sharingGroupName: nil, sharingGroupUUID: UUID(), syncNeeded: false, cloudStorageType: .Dropbox)
        try entry2.insert()

        var count = 0
        try SharingEntry.fetch(db: database) { row in
            count += 1
        }
        
        XCTAssert(count == 2)
    }
    
    func testUpdate() throws {
        try SharingEntry.createTable(db: database)
        try entry.insert()
                
        let replacement = UUID()
        
        entry = try entry.update(setters:
            SharingEntry.sharingGroupUUIDField.description <- replacement
        )
                
        var count = 0
        try SharingEntry.fetch(db: database,
            where: replacement == SharingEntry.sharingGroupUUIDField.description) { row in
            XCTAssert(row.sharingGroupUUID == replacement, "\(row.sharingGroupUUID)")
            count += 1
        }
        
        XCTAssert(entry.sharingGroupUUID == replacement)
        
        XCTAssert(count == 1)
    }
    
    func testDelete() throws {
        try SharingEntry.createTable(db: database)
        try entry.insert()
        
        try entry.delete()
    }
}
