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
import iOSShared

class SharingEntryTests: XCTestCase {
    var database: Connection!
    let uuid = UUID()
    var entry:SharingEntry!
    var userName: String!
    
    override func setUpWithError() throws {
        database = try Connection(.inMemory)
        userName = "Foobly"
        let user = iOSBasics.SharingGroupUser(name: userName)
        
        entry = try SharingEntry(db: database, permission: .admin, deleted: true, sharingGroupName: nil, sharingGroupUUID: uuid, sharingGroupUsers: [user], cloudStorageType: .Dropbox)
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func assertContentsCorrect(entry1: SharingEntry, entry2: SharingEntry) {
        XCTAssert(entry1.sharingGroupUUID == entry2.sharingGroupUUID)
        XCTAssert(entry1.permission == entry2.permission)
        XCTAssert(entry1.deleted == entry2.deleted)
        XCTAssert(entry1.sharingGroupName == entry2.sharingGroupName)
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
        let entry2 = try SharingEntry(db: database, permission: .admin, deleted: true, sharingGroupName: nil, sharingGroupUUID: UUID(), sharingGroupUsers: [SharingGroupUser(name: "Farbly")], cloudStorageType: .Dropbox)
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
    
    func testGetGroupsWithNoGroupsWorks() throws {
        try SharingEntry.createTable(db: database)
        let groups = try SharingEntry.getGroups(db: database)
        XCTAssert(groups.count == 0)
    }
    
    func testGetGroupsWithOneGroupWorks() throws {
        try SharingEntry.createTable(db: database)
        try entry.insert()
        
        let groups = try SharingEntry.getGroups(db: database)
        guard groups.count == 1 else {
            XCTFail()
            return
        }
        
        let group = groups[0]
        
        guard group.sharingGroupUsers.count == 1 else {
            XCTFail()
            return
        }
        
        let user = group.sharingGroupUsers[0]
        XCTAssert(user.name == userName)
    }
    
    func testUpsertWithDeletionChange() throws {
        try SharingEntry.createTable(db: database)
        
        let uuid = UUID().uuidString

        let sharingGroup = ServerShared.SharingGroup()
        sharingGroup.sharingGroupUUID = uuid
        sharingGroup.deleted = false
        sharingGroup.permission = Permission.admin
        sharingGroup.sharingGroupUsers = []
        
        try SharingEntry.upsert(sharingGroup: sharingGroup, db: database)
        
        let rows1 = try SharingEntry.fetch(db: database)
        guard rows1.count == 1 else {
            XCTFail()
            return
        }
        
        let row1 = rows1[0]
        
        XCTAssert(row1.deleted == false)
        
        sharingGroup.deleted = true
        
        try SharingEntry.upsert(sharingGroup: sharingGroup, db: database)

        let rows2 = try SharingEntry.fetch(db: database)
        guard rows2.count == 1 else {
            XCTFail()
            return
        }
        
        let row2 = rows2[0]
        
        XCTAssert(row2.deleted == true)
    }
}
