import SQLite
import Foundation

struct Field<Value, Model: DatabaseModel> {
    let expression:Expression<Value>
    let keyPath: KeyPath<Model, Value>
    
    init(_ expression:Expression<Value>, _ keyPath: KeyPath<Model, Value>) {
        self.expression = expression
        self.keyPath = keyPath
    }
}

class DirectoryEntry: DatabaseModel {
    let db: Connection
    var id: Int64!
    
    //static let fue = Field(Expression<String>("fileUUID"), \T.fileUUID)
    
    static let fileUUIDExpression = Expression<String>("fileUUID")
    var fileUUID: String
    
    static let mimeTypeExpression = Expression<String>("mimeType")
    var mimeType: String
    
    static let fileVersionExpression = Expression<Int64>("fileVersion")
    var fileVersion: Int64
    
    static let sharingGroupUUIDExpression = Expression<String>("sharingGroupUUID")
    var sharingGroupUUID: String

    static let fileGroupUUIDExpression = Expression<String?>("fileGroupUUID")
    var fileGroupUUID: String?
    
    static let appMetaDataExpression = Expression<String?>("appMetaDataUUID")
    var appMetaData: String?

    static let appMetaDataVersionExpression = Expression<Int64?>("appMetaDataVersion")
    var appMetaDataVersion: Int64?

    static let cloudStorageTypeExpression = Expression<String>("cloudStorageType")
    var cloudStorageType: String
    
    /*
    @NSManaged public var deletedLocallyInternal: Bool
    @NSManaged public var deletedOnServer: Bool
    @NSManaged public var goneReasonInternal: String?
    @NSManaged public var forceDownload: Bool
    */
    
    init(db: Connection,
        fileUUID: String,
        mimeType: String,
        fileVersion: Int64,
        sharingGroupUUID: String,
        cloudStorageType: String,
        appMetaData: String? = nil,
        appMetaDataVersion: Int64? = nil,
        fileGroupUUID: String? = nil) {
                
        self.db = db
        self.fileUUID = fileUUID
        self.mimeType = mimeType
        self.fileVersion = fileVersion
        self.sharingGroupUUID = sharingGroupUUID
        self.cloudStorageType = cloudStorageType
        self.appMetaData = appMetaData
        self.appMetaDataVersion = appMetaDataVersion
        self.fileGroupUUID = fileGroupUUID
    }
    
    // MARK: DatabaseModel
    
    static func createTable(db: Connection) throws {
        try startCreateTable(db: db) { t in
            t.column(fileUUIDExpression, primaryKey: true)
            t.column(mimeTypeExpression)
            t.column(fileVersionExpression)
            t.column(sharingGroupUUIDExpression)
            t.column(cloudStorageTypeExpression)
            t.column(appMetaDataExpression)
            t.column(appMetaDataVersionExpression)
            t.column(fileGroupUUIDExpression)
        }
    }
    
    func insert() throws {
        try doInsertRow(db: db, values:
            Self.fileUUIDExpression <- fileUUID,
            Self.mimeTypeExpression <- mimeType,
            Self.fileVersionExpression <- fileVersion,
            Self.sharingGroupUUIDExpression <- sharingGroupUUID,
            Self.cloudStorageTypeExpression <- cloudStorageType,
            Self.appMetaDataExpression <- appMetaData,
            Self.appMetaDataVersionExpression <- appMetaDataVersion,
            Self.fileGroupUUIDExpression <- fileGroupUUID
        )
    }
    
    static func fetch(db: Connection, where: Expression<Bool>,
        rowCallback:(_ row: DirectoryEntry)->()) throws {
        
        try startFetch(db: db, where: `where`) { row in
            let object = DirectoryEntry(db: db,
                fileUUID: row[Self.fileUUIDExpression],
                mimeType: row[Self.mimeTypeExpression],
                fileVersion: row[Self.fileVersionExpression],
                sharingGroupUUID: row[Self.sharingGroupUUIDExpression],
                cloudStorageType: row[Self.cloudStorageTypeExpression],
                appMetaData: row[Self.appMetaDataExpression],
                appMetaDataVersion: row[Self.appMetaDataVersionExpression],
                fileGroupUUID: row[Self.fileGroupUUIDExpression])
            rowCallback(object)
        }
    }
}






