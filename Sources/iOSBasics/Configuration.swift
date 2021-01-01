import Foundation
import Version
import iOSShared

public struct Configuration {
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
    public let cloudFolderName:String?
    
    public let deviceUUID: UUID
    
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
            
    // Only for debugging
    // If you set this to false, and you are testing just within a package, you will see: BackgroundSession <F65F620A-40DF-47D8-8714-90D457380899> an error occurred on the xpc connection to setup the background session: Error Domain=NSCocoaErrorDomain Code=4097
    public let packageTests: Bool
    
    public static var defaultTemporaryFiles: TemporaryFiles {
        let tempDirectoryName = "Temporary"
        let directory = Files.getDocumentsDirectory().appendingPathComponent(tempDirectoryName)
        return TemporaryFiles(directory: directory, filePrefix: "SyncServer", fileExtension: "dat")
    }
    
    public init(appGroupIdentifier: String?, urlSessionBackgroundIdentifier: String? = nil, serverURL: URL, minimumServerVersion:Version?, currentClientAppVersion: Version? = nil, failoverMessageURL:URL?, cloudFolderName:String?, deviceUUID: UUID, temporaryFiles:TemporaryFiles = Self.defaultTemporaryFiles, packageTests: Bool = false) {
        self.appGroupIdentifier = appGroupIdentifier
        self.urlSessionBackgroundIdentifier = urlSessionBackgroundIdentifier
        self.serverURL = serverURL
        self.minimumServerVersion = minimumServerVersion
        self.failoverMessageURL = failoverMessageURL
        self.cloudFolderName = cloudFolderName
        self.deviceUUID = deviceUUID
        self.temporaryFiles = temporaryFiles
        self.currentClientAppVersion = currentClientAppVersion
        
#if !DEBUG
        assert(!packageTests)
#endif

        self.packageTests = packageTests
    }
}
