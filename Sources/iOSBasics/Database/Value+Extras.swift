import SQLite
import Foundation
import ServerShared

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

extension UploadFileTracker.Status: Value {
    public static var declaredDatatype: String {
        return "TEXT"
    }
    
    public static func fromDatatypeValue(_ value: String) -> UploadFileTracker.Status {
        return UploadFileTracker.Status(rawValue: value)!
    }
    
    public var datatypeValue: String {
        return self.rawValue
    }
}

extension DownloadFileTracker.Status: Value {
    public static var declaredDatatype: String {
        return "TEXT"
    }
    
    public static func fromDatatypeValue(_ value: String) -> DownloadFileTracker.Status {
        return DownloadFileTracker.Status(rawValue: value)!
    }
    
    public var datatypeValue: String {
        return self.rawValue
    }
}

extension UploadDeletionTracker.Status: Value {
    public static var declaredDatatype: String {
        return "TEXT"
    }
    
    public static func fromDatatypeValue(_ value: String) -> UploadDeletionTracker.Status {
        return UploadDeletionTracker.Status(rawValue: value)!
    }
    
    public var datatypeValue: String {
        return self.rawValue
    }
}

extension UploadDeletionTracker.DeletionType: Value {
    public static var declaredDatatype: String {
        return "TEXT"
    }
    
    public static func fromDatatypeValue(_ value: String) -> UploadDeletionTracker.DeletionType {
        return UploadDeletionTracker.DeletionType(rawValue: value)!
    }
    
    public var datatypeValue: String {
        return self.rawValue
    }
}

extension UUID: Value {
    public static var declaredDatatype: String {
        return "TEXT"
    }
    
    public static func fromDatatypeValue(_ value: String) -> UUID {
        return UUID(uuidString: value)!
    }
    
    public var datatypeValue: String {
        return self.uuidString
    }
}

extension MimeType: Value {
    public static var declaredDatatype: String {
        return "TEXT"
    }
    
    public static func fromDatatypeValue(_ value: String) -> MimeType {
        return MimeType(rawValue: value)!
    }
    
    public var datatypeValue: String {
        return self.rawValue
    }
}

extension GoneReason: Value {
    public static var declaredDatatype: String {
        return "TEXT"
    }
    
    public static func fromDatatypeValue(_ value: String) -> GoneReason {
        return GoneReason(rawValue: value)!
    }
    
    public var datatypeValue: String {
        return self.rawValue
    }
}

extension CloudStorageType: Value {
    public static var declaredDatatype: String {
        return "TEXT"
    }
    
    public static func fromDatatypeValue(_ value: String) -> CloudStorageType {
        return CloudStorageType(rawValue: value)!
    }
    
    public var datatypeValue: String {
        return self.rawValue
    }
}
