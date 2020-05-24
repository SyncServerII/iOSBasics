
// Handle completion of uploading and downloading.

import Foundation
import ServerShared

// File transfer relies exclusively on delegates because we're using a background URLSession

protocol FileTransferDelegate: AnyObject {
    func error(_ network: Any, file: Filenaming?, statusCode:Int?, error:Error?)

    func downloadError(_ network: Any, file: FilenamingWithAppMetaDataVersion?, statusCode:Int?, error:Error?)
    func downloadCompleted(_ network: Any, file: FilenamingWithAppMetaDataVersion, url: URL?, response: HTTPURLResponse?, _ statusCode:Int?)
    
    func uploadError(_ network: Any, file: Filenaming?, statusCode:Int?, error:Error?)
    func uploadCompleted(_ network: Any, file: Filenaming, response: HTTPURLResponse?, responseBody: [String: Any]?, statusCode:Int?)
}
