import Foundation
import iOSShared
import ServerShared

extension Networking: URLSessionDelegate, URLSessionTaskDelegate, URLSessionDownloadDelegate, URLSessionDataDelegate {

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    
        let originalDownloadLocation = location
        var movedDownloadedFile:URL!
        
        // We do *not* delete the SQLite cache here. `didFinishDownloadingTo` is not the last delegate method to be called for a download. Rather, the `didCompleteWithError` will get called.
        var cache: NetworkCache!
        
        // With an HTTP or HTTPS request, we get HTTPURLResponse back. See https://developer.apple.com/reference/foundation/urlsession/1407613-datatask
        let response = downloadTask.response as? HTTPURLResponse

        logger.info("download completed: location: \( originalDownloadLocation);  status: \(String(describing: response?.statusCode))")

        do {
            cache = try backgroundCache.lookupCache(taskIdentifer: downloadTask.taskIdentifier)
        } catch let error {
            transferDelegate.error(self, file: nil, statusCode: response?.statusCode, error: error)
            return
        }
        
        let downloadFile = FileObject(fileUUID: cache.uuid.uuidString, fileVersion: cache.fileVersion, trackerId: cache.trackerId)

        if response == nil {
            transferDelegate.error(self, file: downloadFile, statusCode: response?.statusCode, error: NetworkingError.couldNotGetHTTPURLResponse)
            return
        }

        // Transfer the temporary file to a more permanent location. Have to do it right now. https://developer.apple.com/reference/foundation/urlsessiondownloaddelegate/1411575-urlsession
        do {
            movedDownloadedFile = try Files.createTemporary(withPrefix: self.config.temporaryFiles.filePrefix, andExtension: self.config.temporaryFiles.fileExtension, inDirectory: self.config.temporaryFiles.directory)
            _ = try FileManager.default.replaceItemAt(movedDownloadedFile, withItemAt: originalDownloadLocation)
        }
        catch (let error) {
            logger.info("Could not move file: \(error)")
            transferDelegate.error(self, file: downloadFile, statusCode: response?.statusCode, error: error)
            return
        }

        switch cache?.transfer {
        case .download:
            do {
                try backgroundCache.cacheDownloadResult(taskIdentifer: downloadTask.taskIdentifier, response: response!, localURL: movedDownloadedFile)
            } catch let error {
                transferDelegate.error(self, file: downloadFile, statusCode: response?.statusCode, error: error)
            }
            
        case .request:
            do {
                try backgroundCache.cacheRequestResult(taskIdentifer: downloadTask.taskIdentifier, response: response!, localURL: movedDownloadedFile)
            } catch let error {
                transferDelegate.error(self, file: downloadFile, statusCode: response?.statusCode, error: error)
            }
            
        case .upload, .none:
            logger.error("Unexpected transfer type: \(String(describing: cache?.transfer))")
            transferDelegate.error(self, file: downloadFile, statusCode: response?.statusCode, error: NetworkingError.unexpectedTransferType)
        }
    }
    
    // For downloads: This gets called even when there was no error, but I believe only it (and not the `didFinishDownloadingTo` method) gets called if there is an error.
    // For uploads: This gets called to indicate successful completion or an error.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    
        var cache: NetworkCache!
        let response = task.response as? HTTPURLResponse

        logger.info("didCompleteWithError: \(String(describing: error)); status: \(String(describing: response?.statusCode))")

        do {
            cache = try backgroundCache.lookupCache(taskIdentifer: task.taskIdentifier)
        } catch let error {
            try? cache?.delete()
            transferDelegate.error(self, file: nil, statusCode: response?.statusCode, error: error)
            return
        }
        
        let file = FileObject(fileUUID: cache.uuid.uuidString, fileVersion: cache.fileVersion, trackerId: cache.trackerId)

        if response == nil {
            try? cache.delete()
            transferDelegate.error(self, file: file, statusCode: response?.statusCode, error: NetworkingError.couldNotGetHTTPURLResponse)
            return
        }

        if let error = error {
            try? cache.delete()
            transferDelegate.error(self, file: file, statusCode: response?.statusCode, error: error)
            return
        }
            
        switch cache.transfer {
        case .upload(let uploadBody):
            transferDelegate.uploadCompleted(self, file: file, response: response, responseBody: uploadBody?.dictionary, statusCode: response?.statusCode)

        case .download(let url):
            transferDelegate.downloadCompleted(self, file: file, url: url, response: response, response?.statusCode)

        case .request(let url):
            transferDelegate.backgroundRequestCompleted(self, url: url, trackerId: file.trackerId, response: response, requestInfo: cache.requestInfo, statusCode: response?.statusCode)
            
        case .none:
            transferDelegate.error(self, file: file, statusCode: response?.statusCode, error: error)
        }
        
        do {
            try cache.delete()
        } catch let error {
            transferDelegate.error(self, file: file, statusCode: response?.statusCode, error: error)
        }
    }
    
    // Apparently the following delegate method is how we get back body data from an upload task: "When the upload phase of the request finishes, the task behaves like a data task, calling methods on the session delegate to provide you with the server’s response—headers, status code, content data, and so on." (see https://developer.apple.com/documentation/foundation/nsurlsessionuploadtask).
    // But, how do we coordinate the status code and error info, apparently received in didCompleteWithError, with this??
    // 1/2/18; Because of this issue I've just now changed how the server upload response gives it's results-- the values now come back in an HTTP header key, just like the download.
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // This assumes this delegate method is called *before* the didCompleteWithError method.
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions(rawValue: UInt(0)))
            if let uploadTask = dataTask as? URLSessionUploadTask,
                let jsonDict = json as? [String: Any] {
                try backgroundCache.cacheUploadResult(taskIdentifer: uploadTask.taskIdentifier, uploadBody: jsonDict)
            }
        } catch let error {
            logger.warning("Could not do JSON conversion: \(error); data.count: \(data.count)")
        }
    }
    
    // This gets called "When all events have been delivered, the system calls the urlSessionDidFinishEvents(forBackgroundURLSession:) method of URLSessionDelegate. At this point, fetch the backgroundCompletionHandler stored by the app delegate in Listing 3 and execute it. Listing 4 shows this process." (https://developer.apple.com/documentation/foundation/url_loading_system/downloading_files_in_the_background)
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        // "Note that because urlSessionDidFinishEvents(forBackgroundURLSession:) may be called on a secondary queue, it needs to explicitly execute the handler (which was received from a UIKit method) on the main queue." (https://developer.apple.com/documentation/foundation/url_loading_system/downloading_files_in_the_background)
        
        DispatchQueue.main.async {
            self.handleEventsForBackgroundURLSessionCompletionHandler?()
            self.handleEventsForBackgroundURLSessionCompletionHandler = nil
        }
    }
    
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
    }
}
