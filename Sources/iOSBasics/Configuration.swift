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
    
    public init(appGroupIdentifier: String?, sqliteDatabasePath: String, serverURL: URL, minimumServerVersion:Version?, failoverMessageURL:URL?, cloudFolderName:String?) {
        self.appGroupIdentifier = appGroupIdentifier
        self.sqliteDatabasePath = sqliteDatabasePath
        self.serverURL = serverURL
        self.minimumServerVersion = minimumServerVersion
        self.failoverMessageURL = failoverMessageURL
        self.cloudFolderName = cloudFolderName
    }
}
