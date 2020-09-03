import SQLite
import Foundation
import ServerShared

// Represents a file that has been uploaded or downloaded in the background.

class UploadBody: Codable, Equatable {
    static func == (lhs: UploadBody, rhs: UploadBody) -> Bool {
        return NSDictionary(dictionary: lhs.dictionary).isEqual(to: rhs.dictionary)
    }
    
    let dictionary: [String: Any]

    init(dictionary: [String: Any]) {
        self.dictionary = dictionary
    }

    enum CodingKeys: String, CodingKey {
        case dictionary
    }

    public required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if values.contains(.dictionary), let jsonData = try? values.decode(Data.self, forKey: .dictionary) {
            dictionary = (try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]) ??  [String: Any]()
        } else {
            dictionary = [String: Any]()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !dictionary.isEmpty, let jsonData = try? JSONSerialization.data(withJSONObject: dictionary) {
            try container.encode(jsonData, forKey: .dictionary)
        }
    }
}
    
enum NetworkTransfer: Codable, Equatable {
    enum NetworkTransferError: Error {
        case badKey
    }
    
    // The associated values are optional because the NetworkTranfer goes through two states: 1) initial creation with a nil associated value, and 2) final value with a non-nil associated value
    case upload(UploadBody?)
    case download(URL?)
    
    enum CodingKeys: String, CodingKey {
        case upload
        case download
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if values.contains(.upload) {
            if let uploadBody = try? values.decode(UploadBody.self, forKey: .upload) {
                self = .upload(uploadBody)
            }
            else {
                self = .upload(nil)
            }
            return
        }
        else if values.contains(.download) {
            if let url = try? values.decode(URL.self, forKey: .download) {
                self = .download(url)
            }
            else {
                self = .download(nil)
            }
            return
        }
        
        throw NetworkTransferError.badKey
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .upload(let upload):
            try container.encode(upload, forKey: .upload)
        case .download(let download):
            try container.encode(download, forKey: .download)
        }
    }
    
    static func == (lhs: NetworkTransfer, rhs: NetworkTransfer) -> Bool {
        switch lhs {
        case .download(let lhsURL):
            switch rhs {
            case .download(let rhsURL):
                return lhsURL == rhsURL
            case .upload:
                return false
            }
            
        case .upload(let lhsBody):
            switch rhs {
            case .download:
                return false
            case .upload(let rhsBody):
                return lhsBody == rhsBody
            }
        }
    }
}


class NetworkCache: DatabaseModel {
    let db: Connection
    var id: Int64!
    
    // URLSessionTask taskIdentifier
    static let taskIdentifierField = Field("taskIdentifier", \M.taskIdentifier)
    var taskIdentifier: Int
    
    static let fileUUIDField = Field("fileUUID", \M.fileUUID)
    var fileUUID: UUID
    
    static let fileVersionField = Field("fileVersion", \M.fileVersion)
    var fileVersion: FileVersionInt?
    
    static let transferField = Field("transfer", \M.transfer)
    var transfer: NetworkTransfer?

    init(db: Connection,
        id: Int64! = nil,
        taskIdentifier: Int,
        fileUUID: UUID,
        fileVersion: FileVersionInt?,
        transfer: NetworkTransfer?) throws {
                
        self.db = db
        self.id = id
        self.taskIdentifier = taskIdentifier
        self.fileUUID = fileUUID
        self.fileVersion = fileVersion
        self.transfer = transfer
    }
    
    // MARK: DatabaseModel
    
    static func createTable(db: Connection) throws {
        try startCreateTable(db: db) { t in
            t.column(idField.description, primaryKey: true)
            t.column(taskIdentifierField.description)
            t.column(fileUUIDField.description)
            t.column(fileVersionField.description)
            t.column(transferField.description)
        }
    }
    
    static func rowToModel(db: Connection, row: Row) throws -> NetworkCache {
        return try NetworkCache(db: db,
            id: row[Self.idField.description],
            taskIdentifier: row[Self.taskIdentifierField.description],
            fileUUID: row[Self.fileUUIDField.description],
            fileVersion: row[Self.fileVersionField.description],
            transfer: row[Self.transferField.description]
        )
    }
    
    func insert() throws {
        try doInsertRow(db: db, values:
            Self.taskIdentifierField.description <- taskIdentifier,
            Self.fileUUIDField.description <- fileUUID,
            Self.fileVersionField.description <- fileVersion,
            Self.transferField.description <- transfer
        )
    }
}






