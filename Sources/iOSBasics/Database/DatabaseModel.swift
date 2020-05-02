import SQLite
import Foundation

enum DatabaseModelError: Error {
    case noId
    case notExactlyOneRowWithId
}

protocol DatabaseModel: class {
    associatedtype T: DatabaseModel
    
    var db: Connection { get }
    var id: Int64! { get set }
        
    // Creating a table when it's already present doesn't throw an error. It has no effect.
    static func createTable(db: Connection) throws
    
    // Insert object as a database row. Assigns the resulting row id to the model.
    func insert() throws
    
    // Fetch rows from the database, constrained by the `where` expression(s).
    static func fetch(db: Connection, where: Expression<Bool>,
        rowCallback:(_ row: T)->()) throws
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
    
    static func startFetch(db: Connection, `where`: Expression<Bool>,
        rowCallback:(_ row: Row)->()) throws {
        
        let query = Self.table.filter(
            `where`
        )
        
        for row in try db.prepare(query) {
            rowCallback(row)
        }
    }
    
    // Update self in the database with the setters.
    func update(db: Connection, setters: SQLite.Setter...) throws {
//        for setter in setters {
//            setter.expression.
//        }
        
        try db.run(Self.table.update(setters))
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
