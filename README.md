# iOSBasics
A basic iOS client for the SyncServerII server.

Enables an iOS app to connect to the SyncServerII server. Intended for use with [iOSSignIn](https://github.com/SyncServerII/iOSSignIn.git) to enable users to sign in and provide user credentials.


# TODO

## Handle background launches after background network requests have completed.

Background network requests are working, but, when completed I believe they are not updating this client.

From the earlier iOS client:
```
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        SyncServer.session.application(application, handleEventsForBackgroundURLSession: identifier, completionHandler: completionHandler)
    }
```

## Background security restrictions

Also have to deal with this. Not sure if SQLite access suffers from any problems this way. It involves file access, which has security restrictions, so maybe.
