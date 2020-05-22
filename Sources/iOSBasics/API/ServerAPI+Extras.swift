import iOSShared
import Foundation

extension ServerAPI {
    func toJSONDictionary(jsonString:String) -> [String:Any]? {
        guard let data = jsonString.data(using: String.Encoding.utf8) else {
            return nil
        }
        
        var json:Any?
        
        do {
            try json = JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions(rawValue: UInt(0)))
        } catch (let error) {
            logger.error("toJSONDictionary: Error in JSON conversion: \(error)")
            return nil
        }
        
        guard let jsonDict = json as? [String:Any] else {
            logger.error("Could not convert json to json Dict")
            return nil
        }
        
        return jsonDict
    }
}
