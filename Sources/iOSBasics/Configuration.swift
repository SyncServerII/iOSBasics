import Foundation
import Version

public struct Configuration {
    // If your app uses an app group identifier to have a shared container between extensions and your app.
    public let appGroupIdentifier: String?
    
    public let sqliteDatabasePath: String
    
    public let serverURL: URL
    public let minimumServerVersion:Version?
    public let failoverMessageURL:URL?

    public let cloudFolderName:String?
    
    public let deviceUUID: UUID
    
    // Only for debugging
    // If you set this to false, and you are testing just within a package, you will see: BackgroundSession <F65F620A-40DF-47D8-8714-90D457380899> an error occurred on the xpc connection to setup the background session: Error Domain=NSCocoaErrorDomain Code=4097
    public let packageTests: Bool
    
    public init(appGroupIdentifier: String?, sqliteDatabasePath: String, serverURL: URL, minimumServerVersion:Version?, failoverMessageURL:URL?, cloudFolderName:String?, deviceUUID: UUID, packageTests: Bool) {
        self.appGroupIdentifier = appGroupIdentifier
        self.sqliteDatabasePath = sqliteDatabasePath
        self.serverURL = serverURL
        self.minimumServerVersion = minimumServerVersion
        self.failoverMessageURL = failoverMessageURL
        self.cloudFolderName = cloudFolderName
        self.deviceUUID = deviceUUID
        
#if !DEBUG
        assert(!packageTests)
#endif

        self.packageTests = packageTests
    }
}
