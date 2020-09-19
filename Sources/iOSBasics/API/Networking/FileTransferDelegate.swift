
// Handle completion of uploading and downloading.

import Foundation
import ServerShared

// File transfer relies exclusively on delegates because we're using a background URLSession

protocol FileTransferDelegate: AnyObject {
    func error(_ network: Any, file: Filenaming?, statusCode:Int?, error:Error?)

    func downloadCompleted(_ network: Any, file: Filenaming, url: URL?, response: HTTPURLResponse?, _ statusCode:Int?)
    
    func uploadCompleted(_ network: Any, file: Filenaming, response: HTTPURLResponse?, responseBody: [String: Any]?, statusCode:Int?)
    
    func backgroundRequestCompleted(_ network: Any, url: URL?, trackerId: Int64, response: HTTPURLResponse?, requestInfo: Data?, statusCode: Int?)
}
