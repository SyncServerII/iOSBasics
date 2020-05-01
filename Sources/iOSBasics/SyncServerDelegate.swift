public protocol SyncServerDelegate: class {
    func syncCompleted()
    
    // Called after a download started by a call to `startDownload` completes.
    func downloadCompleted()
}
