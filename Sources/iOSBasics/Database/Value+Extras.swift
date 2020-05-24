import SQLite
import Foundation

// Extensions for SQLite support.

extension URL: Value {
    public static var declaredDatatype: String {
        return Blob.declaredDatatype
    }
    
    public static func fromDatatypeValue(_ blobValue: Blob) -> URL {
        let decoder = JSONDecoder()
        return try! decoder.decode(URL.self, from: Data.fromDatatypeValue(blobValue))
    }
    
    public var datatypeValue: Blob {
        let encoder = JSONEncoder()
        return try! encoder.encode(self).datatypeValue
    }
}

// With the following, SQLite crashes: Thread 1: Fatal error: tried to bind unexpected value 1
/*
extension Int32 : Number, Value {
    public static let declaredDatatype = "INTEGER"

    public static func fromDatatypeValue(_ datatypeValue: Int32) -> Int32 {
        return datatypeValue
    }

    public var datatypeValue: Int32 {
        return self
    }
}
*/

extension Int32: Value {
    public static var declaredDatatype: String {
        return Blob.declaredDatatype
    }
    
    public static func fromDatatypeValue(_ blobValue: Blob) -> Int32 {
        let decoder = JSONDecoder()
        return try! decoder.decode(Int32.self, from: Data.fromDatatypeValue(blobValue))
    }
    
    public var datatypeValue: Blob {
        let encoder = JSONEncoder()
        return try! encoder.encode(self).datatypeValue
    }
}

extension HTTPURLResponse: Value {
    public static var declaredDatatype: String {
        return Blob.declaredDatatype
    }
    
    public static func fromDatatypeValue(_ blobValue: Blob) -> HTTPURLResponse {
        return try! NSKeyedUnarchiver.unarchivedObject(ofClass: HTTPURLResponse.self, from: Data.fromDatatypeValue(blobValue))!
    }
    
    public var datatypeValue: Blob {
        return try! NSKeyedArchiver.archivedData(withRootObject: self, requiringSecureCoding: true).datatypeValue
    }
}

extension NetworkTransfer: Value {
    public static var declaredDatatype: String {
        return Blob.declaredDatatype
    }
    
    public static func fromDatatypeValue(_ blobValue: Blob) -> NetworkTransfer {
        let decoder = JSONDecoder()
        return try! decoder.decode(NetworkTransfer.self, from: Data.fromDatatypeValue(blobValue))
    }
    
    public var datatypeValue: Blob {
        let encoder = JSONEncoder()
        return try! encoder.encode(self).datatypeValue
    }
}
