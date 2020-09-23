import Foundation
import Version
import iOSShared

public struct Configuration {
    // If your app uses an app group identifier to have a shared container between extensions and your app.
    public let appGroupIdentifier: String?
        
    public let serverURL: URL

    public var baseURL: String {
        return serverURL.absoluteString
    }
    
    public let minimumServerVersion:Version?
    public let failoverMessageURL:URL?

    public let cloudFolderName:String?
    
    public let deviceUUID: UUID
    
    public struct TemporaryFiles {
        public let directory:URL
        public let filePrefix:String
        public let fileExtension:String
        
        init(directory:URL, filePrefix:String, fileExtension:String) {
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
    
    public init(appGroupIdentifier: String?, serverURL: URL, minimumServerVersion:Version?, failoverMessageURL:URL?, cloudFolderName:String?, deviceUUID: UUID, temporaryFiles:TemporaryFiles = Self.defaultTemporaryFiles, packageTests: Bool = false) {
        self.appGroupIdentifier = appGroupIdentifier
        self.serverURL = serverURL
        self.minimumServerVersion = minimumServerVersion
        self.failoverMessageURL = failoverMessageURL
        self.cloudFolderName = cloudFolderName
        self.deviceUUID = deviceUUID
        self.temporaryFiles = temporaryFiles
        
#if !DEBUG
        assert(!packageTests)
#endif

        self.packageTests = packageTests
    }
}
