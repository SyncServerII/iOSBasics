import Foundation
import iOSShared
import ServerShared

// Originally I had the serial queue usage as async here. But that seriously breaks things. See https://stackoverflow.com/questions/66416160
// The `backgroundAsssertable` usage is here to try to deal with https://github.com/SyncServerII/Neebla/issues/7#issuecomment-802978539 which stem from callbacks/notifications due to networking delegate calls.

extension Networking: URLSessionDelegate, URLSessionTaskDelegate, URLSessionDownloadDelegate, URLSessionDataDelegate {

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {

        try? backgroundAsssertable.syncRun { [weak self] in
            guard let self = self else { return }

            self.serialQueue.sync { [weak self] in
                guard let self = self else { return }
                
                self.urlSessionHelper(session, downloadTask: downloadTask, didFinishDownloadingTo: location)
            }
        } expiry: { [weak self] in
            guard let self = self else { return }
            self.transferDelegate.error(self, file: nil, statusCode: nil, error: SyncServerError.backgroundAssertionExpired)
        }
    }
    
    // For downloads: This gets called even when there was no error, but I believe only it (and not the `didFinishDownloadingTo` method) gets called if there is an error.
    // For uploads: This gets called to indicate successful completion or an error.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {

        try? backgroundAsssertable.syncRun { [weak self] in
            guard let self = self else { return }

            self.serialQueue.sync { [weak self] in
                guard let self = self else { return }
                
                self.urlSessionHelper(session, task: task, didCompleteWithError: error)
            }
        } expiry: { [weak self] in
            guard let self = self else { return }
            self.transferDelegate.error(self, file: nil, statusCode: nil, error: SyncServerError.backgroundAssertionExpired)
        }
    }
    
    // Apparently the following delegate method is how we get back body data from an upload task: "When the upload phase of the request finishes, the task behaves like a data task, calling methods on the session delegate to provide you with the server’s response—headers, status code, content data, and so on." (see https://developer.apple.com/documentation/foundation/nsurlsessionuploadtask).
    // But, how do we coordinate the status code and error info, apparently received in didCompleteWithError, with this??
    // 1/2/18; Because of this issue I've just now changed how the server upload response gives it's results-- the values now come back in an HTTP header key, just like the download.
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    
        try? backgroundAsssertable.syncRun { [weak self] in
            guard let self = self else { return }

            self.serialQueue.sync { [weak self] in
                guard let self = self else { return }
                
                self.urlSessionHelper(session, dataTask: dataTask, didReceive: data)
            }
        } expiry: { [weak self] in
            guard let self = self else { return }
            self.transferDelegate.error(self, file: nil, statusCode: nil, error: SyncServerError.backgroundAssertionExpired)
        }
    }
    
    // This gets called "When all events have been delivered, the system calls the urlSessionDidFinishEvents(forBackgroundURLSession:) method of URLSessionDelegate. At this point, fetch the backgroundCompletionHandler stored by the app delegate in Listing 3 and execute it. Listing 4 shows this process." (https://developer.apple.com/documentation/foundation/url_loading_system/downloading_files_in_the_background)
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    
        try? backgroundAsssertable.syncRun { [weak self] in
            guard let self = self else { return }
            self.serialQueue.sync { [weak self] in
                guard let self = self else { return }
                
                self.urlSessionDidFinishEventsHelper(forBackgroundURLSession: session)
            }
        } expiry: { [weak self] in
            guard let self = self else { return }
            self.transferDelegate.error(self, file: nil, statusCode: nil, error: SyncServerError.backgroundAssertionExpired)
        }
    }
    
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        logger.error("didBecomeInvalidWithError: \(String(describing: error))")
    }
}

