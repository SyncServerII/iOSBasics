import Foundation
import Version

public struct Configuration {
    // If your app uses an app group identifier to have a shared container between extensions and your app.
    let appGroupIdentifier: String?
    
    let sqliteDatabasePath: String
    
    let serverURL: URL
    let minimumServerVersion:Version?
    let failoverMessageURL:URL?

    let cloudFolderName:String?
}
