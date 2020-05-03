import SQLite
import Foundation

enum DatabaseModelError: Error {
    case noId
    case notExactlyOneRowWithId
}

// I'd like to be able to automatically extract the property name from the KeyPath. That would make it so that I can omit one parameter from this field structure. But it looks like that's not supported yet. See https://forums.swift.org/t/pitch-improving-keypath/6541
struct Field<FieldType, Model: DatabaseModel> {
    let description:Expression<FieldType>
    var keyPath: ReferenceWritableKeyPath<Model, FieldType>
    
    init(_ fieldName:String, _ keyPath: ReferenceWritableKeyPath<Model, FieldType>) {
        self.description = Expression<FieldType>(fieldName)
        self.keyPath = keyPath
    }
}

protocol DatabaseModel: class {
    associatedtype M: DatabaseModel
    
    var db: Connection { get }
    var id: Int64! { get set }
    
    // Creating a table when it's already present doesn't throw an error. It has no effect.
    static func createTable(db: Connection) throws
    
    static func rowToModel(db: Connection, row: Row) throws -> M

    // Insert object as a database row. Assigns the resulting row id to the model.
    func insert() throws
}

extension DatabaseModel {    
    static var table: Table {
        let tableName = String(describing: Self.self)
        return Table(tableName)
    }
    
    static func startCreateTable(db: Connection, block: (TableBuilder) -> Void) throws {
        try db.run(table.create(ifNotExists: true) { t in
            block(t)
        })
    }
    
    // Assigns the resulting row id to the model.
    func doInsertRow(db: Connection, values: SQLite.Setter...) throws {
        let row = Self.table.insert(values)
        let id = try db.run(row)
        self.id = id
    }
    
    // Fetch rows from the database, constrained by the `where` expression(s).
    // Pass `where` as nil to fetch all records.
    static func fetch(db: Connection, `where`: Expression<Bool>? = nil,
        rowCallback:(_ model: M)->()) throws {
        
        let query: QueryType
        
        if let `where` = `where` {
            query = Self.table.filter(
                `where`
            )
        }
        else {
            query = Self.table
        }
        
        for row in try db.prepare(query) {
            let model = try rowToModel(db: db, row: row)
            rowCallback(model)
        }
    }
    
    static func fetch(db: Connection, withId id: Int64) throws -> Row {
        let query = Self.table.filter(
            id == rowid
        )
        
        guard try db.scalar(query.count) == 1 else {
            throw DatabaseModelError.notExactlyOneRowWithId
        }
        
        guard let row = try db.pluck(query) else {
            throw DatabaseModelError.notExactlyOneRowWithId
        }
        
        return row
    }
        
    // Update the row in the database with the setters.
    // Returns a copy of the model with the fields updated.
    @discardableResult
    func update(setters: SQLite.Setter...) throws -> M {
        try db.run(Self.table.update(setters))
        let row = try Self.fetch(db: db, withId: self.id)
        return try Self.rowToModel(db: db, row: row)
    }
    
    // Delete the database row.
    func delete() throws {
        guard let id = id else {
            throw DatabaseModelError.noId
        }
        
        let query = Self.table.filter(id == rowid)

        guard try db.scalar(query.count) == 1 else {
            throw DatabaseModelError.notExactlyOneRowWithId
        }

        try db.run(query.delete())
    }
}
