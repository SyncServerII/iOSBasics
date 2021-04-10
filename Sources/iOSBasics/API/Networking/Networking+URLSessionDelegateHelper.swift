//
//  Networking+URLSessionDelegateHelper.swift
//  
//
//  Created by Christopher G Prince on 2/28/21.
//

import Foundation
import iOSShared
import ServerShared

extension Networking {
    func urlSessionHelper(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    
        let originalDownloadLocation = location
        var movedDownloadedFile:URL!
        
        // We do *not* delete the SQLite cache here. `didFinishDownloadingTo` is not the last delegate method to be called for a download. Rather, the `didCompleteWithError` will get called.
        var cache: NetworkCache!
        
        // With an HTTP or HTTPS request, we get HTTPURLResponse back. See https://developer.apple.com/reference/foundation/urlsession/1407613-datatask
        let possiblyNilResponse = downloadTask.response as? HTTPURLResponse

        logger.info("download completed: location: \(originalDownloadLocation);  status: \(String(describing: possiblyNilResponse?.statusCode))")

        do {
            cache = try backgroundCache.lookupCache(taskIdentifer: downloadTask.taskIdentifier)
        } catch let error {
            transferDelegate.error(self, file: nil, statusCode: possiblyNilResponse?.statusCode, error: error)
            return
        }
        
        let downloadFile = FileObject(fileUUID: cache.uuid.uuidString, fileVersion: cache.fileVersion, trackerId: cache.trackerId)

        guard let response = possiblyNilResponse else {
            logger.error("urlSessionHelper: couldNotGetHTTPURLResponse")
            transferDelegate.error(self, file: downloadFile, statusCode: possiblyNilResponse?.statusCode, error: NetworkingError.couldNotGetHTTPURLResponse)
            return
        }
        
        guard versionsAreOK(headerFields: response.allHeaderFields) else {
            return
        }

        // Transfer the temporary file to a more permanent location. Have to do it right now. https://developer.apple.com/reference/foundation/urlsessiondownloaddelegate/1411575-urlsession
        do {
            movedDownloadedFile = try Files.createTemporary(withPrefix: self.config.temporaryFiles.filePrefix, andExtension: self.config.temporaryFiles.fileExtension, inDirectory: self.config.temporaryFiles.directory)
            _ = try FileManager.default.replaceItemAt(movedDownloadedFile, withItemAt: originalDownloadLocation)
        }
        catch (let error) {
            logger.info("Could not move file: \(error)")
            transferDelegate.error(self, file: downloadFile, statusCode: response.statusCode, error: error)
            return
        }
        
        logger.info("Downloaded and moved file: \(String(describing: movedDownloadedFile))")
#if DEBUG
        if let movedDownloadedFile = movedDownloadedFile,
            let data = try? Data(contentsOf: movedDownloadedFile) {
            let string = String(data: data, encoding: .utf8)?.prefix(200)
            logger.debug("Downloaded file contents: \(String(describing: string))")
        }
#endif

        switch cache?.transfer {
        case .download:
            do {
                try backgroundCache.cacheDownloadResult(taskIdentifer: downloadTask.taskIdentifier, response: response, localURL: movedDownloadedFile)
            } catch let error {
                transferDelegate.error(self, file: downloadFile, statusCode: response.statusCode, error: error)
            }
            
        case .request:
            do {
                try backgroundCache.cacheRequestResult(taskIdentifer: downloadTask.taskIdentifier, response: response, localURL: movedDownloadedFile)
            } catch let error {
                transferDelegate.error(self, file: downloadFile, statusCode: response.statusCode, error: error)
            }
            
        case .upload, .none:
            logger.error("Unexpected transfer type: \(String(describing: cache?.transfer))")
            transferDelegate.error(self, file: downloadFile, statusCode: response.statusCode, error: NetworkingError.unexpectedTransferType)
        }
    }

    private func validStatusCode(_ statusCode: Int?) -> Bool {
        if let statusCode = statusCode, statusCode >= 200, statusCode <= 299 {
            return true
        }
        else {
            return false
        }
    }
    
    func urlSessionHelper(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    
        var cache: NetworkCache!
        let taskResponse = task.response as? HTTPURLResponse

        logger.info("didCompleteWithError: \(String(describing: error)); status: \(String(describing: taskResponse?.statusCode))")

        do {
            cache = try backgroundCache.lookupCache(taskIdentifer: task.taskIdentifier)
        } catch let error {
            try? cache?.delete()
            // May not have the cache. Responding with generic error.
            transferDelegate.error(self, file: nil, statusCode: taskResponse?.statusCode, error: error)
            return
        }
        
        let file = FileObject(fileUUID: cache.uuid.uuidString, fileVersion: cache.fileVersion, trackerId: cache.trackerId)
        
        func errorResponse(error: Error) {
            switch cache.transfer {
            case .download:
                transferDelegate.downloadCompleted(self, file: file, event: .failure(error: error, statusCode: taskResponse?.statusCode, responseHeaders: taskResponse?.allHeaderFields), response: taskResponse)
            
            case .upload:
                transferDelegate.uploadCompleted(self, file: file, event: .failure(error: error, statusCode: taskResponse?.statusCode, responseHeaders: taskResponse?.allHeaderFields), response: taskResponse)
                
            case .request, .none:
                transferDelegate.error(self, file: file, statusCode: taskResponse?.statusCode, error: error)
            }
        }
        
        guard let response = taskResponse else {
            // The background request failed. I'm assuming that this is definitive and that the request will not be retried automatically by iOS. So, am removing the NetworkCache object.
            try? cache.delete()
            logger.error("urlSessionHelper: The background request failed: couldNotGetHTTPURLResponse")
            errorResponse(error: NetworkingError.couldNotGetHTTPURLResponse)
            return
        }

        guard versionsAreOK(headerFields: response.allHeaderFields) else {
            return
        }
        
        if let error = error {
            // Same kind of assumption as above.
            try? cache.delete()
            errorResponse(error: error)
            return
        }
                    
        switch cache.transfer {
        case .upload(let uploadBody):
            if response.statusCode == HTTPStatus.gone.rawValue {
                transferDelegate.uploadCompleted(self, file: file, event: .gone(responseBody: uploadBody?.dictionary), response: response)
            }
            else if validStatusCode(response.statusCode) {
                transferDelegate.uploadCompleted(self, file: file, event: .success(responseBody: uploadBody?.dictionary), response: response)
            }
            else {
                transferDelegate.uploadCompleted(self, file: file, event: .failure(error: nil, statusCode: response.statusCode, responseHeaders: response.allHeaderFields), response: response)
            }

        case .download(let url):
            if validStatusCode(response.statusCode), let url = url {
                transferDelegate.downloadCompleted(self, file: file, event: .success(url), response: response)
            }
            else {
                transferDelegate.downloadCompleted(self, file: file, event: .failure(error: nil, statusCode: response.statusCode, responseHeaders: response.allHeaderFields), response: response)
            }

        case .request(let url):
            transferDelegate.backgroundRequestCompleted(self, url: url, trackerId: file.trackerId, response: response, requestInfo: cache.requestInfo, statusCode: response.statusCode)
            
        case .none:
            transferDelegate.error(self, file: file, statusCode: response.statusCode, error: error)
        }
        
        do {
            try cache.delete()
        } catch let error {
            transferDelegate.error(self, file: file, statusCode: response.statusCode, error: error)
        }
    }
    
    func urlSessionHelper(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // This assumes this delegate method is called *before* the didCompleteWithError method.
        guard data.count > 0 else {
            return
        }
        
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions(rawValue: UInt(0)))
            if let uploadTask = dataTask as? URLSessionUploadTask,
                let jsonDict = json as? [String: Any] {
                try backgroundCache.cacheUploadResult(taskIdentifer: uploadTask.taskIdentifier, uploadBody: jsonDict)
            }
        } catch let error {
            let str = String(data: data, encoding: .utf8)
            logger.warning("Could not do JSON conversion: \(error); data.count: \(data.count); string: \(String(describing: str))")
        }
    }
    
    func urlSessionDidFinishEventsHelper(forBackgroundURLSession session: URLSession) {
        // "Note that because urlSessionDidFinishEvents(forBackgroundURLSession:) may be called on a secondary queue, it needs to explicitly execute the handler (which was received from a UIKit method) on the main queue." (https://developer.apple.com/documentation/foundation/url_loading_system/downloading_files_in_the_background)
        
        DispatchQueue.main.async {
            self.handleEventsForBackgroundURLSessionCompletionHandler?()
            self.handleEventsForBackgroundURLSessionCompletionHandler = nil
        }
    }
}
