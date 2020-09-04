import SQLite
import Foundation

enum DatabaseModelError: Error {
    case noId
    case notExactlyOneRowWithId
    case moreThanOneRowInResult
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

protocol DatabaseModel: AnyObject {
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
    static var idField: Field<Int64, M> {
        return Field("id", \M.id)
    }
    
    static var table: Table {
        let tableName = String(describing: Self.self)
        return Table(tableName)
    }
    
    static func startCreateTable(db: Connection, block: (TableBuilder) -> Void) throws {
        try db.run(table.create(ifNotExists: true) { t in
            block(t)
        })
    }
    
    // Assigns the resulting row id to the model. SQLite automatically puts the id into the inserted row as well. Seems to do this just as a result of having an id column.
    func doInsertRow(db: Connection, values: SQLite.Setter...) throws {
        let row = Self.table.insert(values)
        let id = try db.run(row)
        
        // Put the id in the returned object
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
    
    static func fetch(db: Connection, `where`: Expression<Bool>? = nil) throws -> [M] {
        let query: QueryType
        
        if let `where` = `where` {
            query = Self.table.filter(
                `where`
            )
        }
        else {
            query = Self.table
        }
        
        var result = [M]()
        for row in try db.prepare(query) {
            let model = try rowToModel(db: db, row: row)
            result += [model]
        }
        
        return result
    }
    
    
    
    // There must be 0 or 1 rows in the expected result.
    static func fetchSingleRow(db: Connection, `where`: Expression<Bool>) throws -> M? {
        var count = 0
        var result: M?
        
        try fetch(db: db,
            where: `where`) { row in
            count += 1
            result = row
        }
        
        if count > 1 {
            throw DatabaseModelError.moreThanOneRowInResult
        }
        
        return result
    }
    
    // Use this only when you are expecting 0 or 1 rows to match the where expression.
    static func isRow(db: Connection, `where`: Expression<Bool>) throws -> Bool {
        guard let _ = try fetchSingleRow(db: db, where: `where`) else {
            return false
        }
        
        return true
    }
    
    // Returns the number of rows matching the `where` expression or in table if nil.
    static func numberRows(db: Connection, `where`: Expression<Bool>? = nil) throws -> Int {
       let query: Table
        
        if let `where` = `where` {
            query = Self.table.filter(
                `where`
            )
        }
        else {
            query = Self.table
        }
        
        return try db.scalar(query.count)
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
        
    // Update the row in the database with the setters on the basis of the current id field.
    // Returns a copy of the model with the fields updated.
    @discardableResult
    func update(setters: SQLite.Setter...) throws -> M {
        guard let id = id else {
            throw DatabaseModelError.noId
        }
        
        try db.run(Self.table.update(setters))
        let row = try Self.fetch(db: db, withId: id)
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
