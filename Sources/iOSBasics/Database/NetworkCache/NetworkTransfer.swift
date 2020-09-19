import Foundation

enum NetworkTransfer: Codable, Equatable {
    enum NetworkTransferError: Error {
        case badKey
    }
    
    // The associated values are optional because the NetworkTranfer goes through two states: 1) initial creation with a nil associated value, and 2) final value with a non-nil associated value
    case upload(UploadBody?)
    case download(URL?)
    
    // A general purpose HTTP request, e.g., for upload deletion. Treating it akin to a download. The result from the request will be stored in a file.
    case request(URL?)
    
    enum CodingKeys: String, CodingKey {
        case upload
        case download
        case request
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
        else if values.contains(.request) {
            if let url = try? values.decode(URL.self, forKey: .request) {
                self = .request(url)
            }
            else {
                self = .request(nil)
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
        case .request(let download):
            try container.encode(download, forKey: .request)
        }
    }
    
    static func == (lhs: NetworkTransfer, rhs: NetworkTransfer) -> Bool {
        switch lhs {
        case .download(let lhsURL):
            switch rhs {
            case .download(let rhsURL):
                return lhsURL == rhsURL
            case .upload, .request:
                return false
            }
            
        case .upload(let lhsBody):
            switch rhs {
            case .download, .request:
                return false
            case .upload(let rhsBody):
                return lhsBody == rhsBody
            }

        case .request(let lhsURL):
            switch rhs {
            case .download, .upload:
                return false
            case .request(let rhsURL):
                return lhsURL == rhsURL
            }
        }
    }
}
