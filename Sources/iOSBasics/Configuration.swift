public struct User {
}

public struct FileType: Hashable {
    let mimeType: String
    
    // Needs elaboration!!
    let conflictResolutionStrategy: String
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(mimeType)
    }
}

public struct Configuration {
    let user: User
    
    // If your app uses an app group identifier to have a shared container between extensions and your app.
    let appGroupIdentifier: String?
    
    let sqliteDatabasePath: String
    
    let fileTypes: Set<FileType>
}
