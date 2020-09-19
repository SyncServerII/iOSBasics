
import Foundation

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
