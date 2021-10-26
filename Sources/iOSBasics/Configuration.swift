import Foundation
import Version
import iOSShared

protocol ExpiryConfigurable {
    var expiryDuration: TimeInterval { get }
}

public struct Configuration: ExpiryConfigurable {
    // https://stackoverflow.com/questions/26172783
    // https://stackoverflow.com/questions/25438709
    // If your app uses an app group identifier to have a shared container between extensions and your app.
    public let appGroupIdentifier: String?
    
    public let urlSessionBackgroundIdentifier: String?
    
    public let serverURL: URL

    public var baseURL: String {
        return serverURL.absoluteString
    }
    
    public let minimumServerVersion:Version?
    
    // The version of the current client app, e.g., Neebla
    public let currentClientAppVersion:Version?
    
    public let failoverMessageURL:URL?

    // The name of the folder to use in cloud storage for services that need a folder name. E.g., Google Drive.
    // For some cloud storage services, this is the default. E.g., for Solid Pod's.
    public let cloudFolderName:String?
    
    public let deviceUUID: UUID
    
    // See https://developer.apple.com/documentation/foundation/nsurlsessionconfiguration/1408259-timeoutintervalforrequest
    public static let defaultTimeoutIntervalForRequest:TimeInterval = 60 // 1 minute
    public let timeoutIntervalForRequest: TimeInterval
    
    // See https://developer.apple.com/documentation/foundation/nsurlsessionconfiguration/1408153-timeoutintervalforresource
    public static let defaultTimeoutIntervalForResource:TimeInterval = 60 * 30 // 1/2 hour
    
    public let timeoutIntervalForResource: TimeInterval
    
    // The maximum number of file groups that can be concurrently uploaded. Each of these file groups can have some number of files.
    // See https://github.com/SyncServerII/Neebla/issues/15#issuecomment-861097721
    public static let defaultMaxConcurrentFileGroupUploads:Int = 5
    public let maxConcurrentFileGroupUploads: Int
    
    // The number of seconds to allow before retrying a file upload, deletion, or download if the request hasn't already completed in this time. The current default of 3 hours is probably too long. Probably this should be only slightly longer than the expiry of any access token for any account type that we're using in the app. Since, once an request is triggered it has the same access token.
    // public static let defaultExpiryDuration:TimeInterval = 60 * 60 * 3 // 3 hours
    public static let defaultExpiryDuration:TimeInterval = 60 * 10
    
    // Used for file uploads, upload deletions, and downloads.
    public let expiryDuration: TimeInterval
    
    /// This is for debugging; if you set this to `false`, then no uploads and downloads will take place. In that case, uploads and downloads will only be queued for later. Similarly, deletions too will be queued.
    public let allowUploadDownload: Bool
    
    /// Provide details about temporary files.
    ///
    /// - Parameters:
    ///     - directory: e.g., Give a specific path to a /Documents directory
    ///         subdirectory to store temp files.
    ///     - filePrefix: A prefix to give these files. E.g., "Neebla"
    ///     - fileExtension: A file extension to give these files. E.g., "dat"
    public struct TemporaryFiles {
        public let directory:URL
        public let filePrefix:String
        public let fileExtension:String
        
        public init(directory:URL, filePrefix:String, fileExtension:String) {
            self.directory = directory
            self.filePrefix = filePrefix
            self.fileExtension = fileExtension
        }
    }
    
    public let temporaryFiles: TemporaryFiles
    
    // After initial upload of a change to a mutable file has completed, polling is carried out to check for finalization of the deferrred upload. This is the interval of that polling. If given as nil, this check is not carried out.
    public static let defaultDeferredCheckInterval:TimeInterval = 2
    public let deferredCheckInterval: TimeInterval?
            
    // Only for debugging
    // If you set this to false, and you are testing just within a package, you will see: BackgroundSession <F65F620A-40DF-47D8-8714-90D457380899> an error occurred on the xpc connection to setup the background session: Error Domain=NSCocoaErrorDomain Code=4097
    public let packageTests: Bool
    
    public static var defaultTemporaryFiles: TemporaryFiles {
        let tempDirectoryName = "Temporary"
        let directory = Files.getDocumentsDirectory().appendingPathComponent(tempDirectoryName)
        return TemporaryFiles(directory: directory, filePrefix: "SyncServer", fileExtension: "dat")
    }
    
    // Set this with care: 1) There are limits based on server configuration,
    // and 2) it can strongly affect server performance.
    public static let defaultMaxFileSizeBytes: Int = 1024 * 1024 * 10
    public let maxFileSizeBytes: Int
    
    public init(appGroupIdentifier: String?, urlSessionBackgroundIdentifier: String? = nil, serverURL: URL, minimumServerVersion:Version?, currentClientAppVersion: Version? = nil, failoverMessageURL:URL?, cloudFolderName:String?, deviceUUID: UUID, temporaryFiles:TemporaryFiles = Self.defaultTemporaryFiles, packageTests: Bool = false, timeoutIntervalForRequest: TimeInterval = Self.defaultTimeoutIntervalForRequest, timeoutIntervalForResource: TimeInterval = Self.defaultTimeoutIntervalForResource,
        deferredCheckInterval: TimeInterval? = Self.defaultDeferredCheckInterval,
        maxConcurrentFileGroupUploads: Int = Self.defaultMaxConcurrentFileGroupUploads,
        expiryDuration: TimeInterval = Self.defaultExpiryDuration,
        allowUploadDownload: Bool = true,
        maxFileSizeBytes: Int = Self.defaultMaxFileSizeBytes) {
        
        self.appGroupIdentifier = appGroupIdentifier
        self.urlSessionBackgroundIdentifier = urlSessionBackgroundIdentifier
        self.serverURL = serverURL
        self.minimumServerVersion = minimumServerVersion
        self.failoverMessageURL = failoverMessageURL
        self.cloudFolderName = cloudFolderName
        self.deviceUUID = deviceUUID
        self.temporaryFiles = temporaryFiles
        self.currentClientAppVersion = currentClientAppVersion
        self.timeoutIntervalForRequest = timeoutIntervalForRequest
        self.timeoutIntervalForResource = timeoutIntervalForResource
        self.deferredCheckInterval = deferredCheckInterval
        self.maxConcurrentFileGroupUploads = maxConcurrentFileGroupUploads
        self.expiryDuration = expiryDuration
        self.allowUploadDownload = allowUploadDownload
        self.maxFileSizeBytes = maxFileSizeBytes
        
#if !DEBUG
        assert(!packageTests)
#endif

        self.packageTests = packageTests
    }
}
