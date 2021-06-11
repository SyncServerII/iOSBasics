
// Handle completion of uploading and downloading.

import Foundation
import ServerShared

// File transfer relies exclusively on delegates because we're using a background URLSession

enum FileTransferDownloadEvent {
    // 2XX status code
    case success(URL)
    
    // Non-2XX status code or other failure. Download needs to be retried by app.
    case failure(error: Error?, statusCode:Int?, responseHeaders:[AnyHashable: Any]?)
}

enum FileTransferUploadEvent {
    // 2XX status code
    case success(responseBody: [String: Any]?)
    
    // HTTPStatus.gone
    case gone(responseBody: [String: Any]?)
    
    // HTTPStatus.conflict
    case conflict(responseBody: [String: Any]?)
    
    // Non-2XX status code (and non-gone) or other failure. Upload needs to be retried by app.
    case failure(error: Error?, statusCode:Int?, responseHeaders:[AnyHashable: Any]?)
}

protocol FileTransferDelegate: AnyObject {
    func error(_ network: Any, file: Filenaming?, statusCode:Int?, error:Error?)

    func downloadCompleted(_ network: Any, file: Filenaming, event: FileTransferDownloadEvent, response: HTTPURLResponse?)
    
    func uploadCompleted(_ network: Any, file: Filenaming, event: FileTransferUploadEvent, response: HTTPURLResponse?)
    
    func backgroundRequestCompleted(_ network: Any, url: URL?, trackerId: Int64, response: HTTPURLResponse?, requestInfo: Data?, statusCode: Int?)
}
