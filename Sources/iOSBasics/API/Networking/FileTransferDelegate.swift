
// Handle completion of uploading and downloading.

import Foundation
import ServerShared

// File transfer relies exclusively on delegates because we're using a background URLSession

enum FileTransferDownloadEvent {
    // 2XX status code
    case success(URL)
    
    // Non-2XX status code or other failure. Download needs to be retried by app.
    case failure(error: Error?, statusCode:Int?)
}

protocol FileTransferDelegate: AnyObject {
    func error(_ network: Any, file: Filenaming?, statusCode:Int?, error:Error?)

    func downloadEnded(_ network: Any, file: Filenaming, event: FileTransferDownloadEvent, response: HTTPURLResponse?)
    
    func uploadCompleted(_ network: Any, file: Filenaming, response: HTTPURLResponse?, responseBody: [String: Any]?, statusCode:Int?)
    
    func backgroundRequestCompleted(_ network: Any, url: URL?, trackerId: Int64, response: HTTPURLResponse?, requestInfo: Data?, statusCode: Int?)
}
