# TODO

## Sign-in flow with an invitation.
I've not yet taken this into account with the new sign-in packages.

##  func completeSignInProcess(autoSignIn:Bool)
I've also not implemented this in the iOSFacebook package. It wasn't appropriate for this location.

I want to check if this exact piece of code has been repeated in the other sign-in packages.

Where should this go? In the SignInManager?

## Don't allow the user to sign in as a different user.
i.e., if they have signed as one user, and downloaded data, and then sign-out and try to sign in as a different user.

## Need work and testing on silent-sign in
l.e., auto sign in

## Put ServerResponseCheck back

## Put checkForNetworkAndReport ??

## DropboxSavedCreds has changed and won't read data properly from NSUserDefaults.

## Why is the ServerAPI addUser only using a sharingGroupUUID if there is a cloud folder?
Answer: I believe this was an error in the code. addUser always needs to create a sharing group.

## Where is the retry mechanism if the access token need to be refreshed?

## Why does an access token come back from the API checkCreds call? 

## Get rid of undeletion.
Take a stronger stance. Simplify.

## Upload gone not in upload yet.
Why does the gone reason come back in the body where the rest of the response result comes back in the header. See ServerAPI upload.

## contentsChangedOnServer needs documentation in download.

## ServerResponseCheck.session.failover not in networking, along with ServerResponseCheck.session.minimumIOSClientVersion-- I think this is on the iOS Client.

## Need to put Hashing.hashOf in specific cloud storage libraries
[Moved to: https://github.com/SyncServerII/ServerMain/issues/2]

## [DONE] Need the equivalent of "sign in using SyncServer Example client"-- to  get credentials for testing. See TestConfiguration.swift in the Server.
[Now in https://github.com/SyncServerII/iOSSignInTesting.git]

## [DONE] Server: Need to put something like this back in, for MockStorage:
```
extension Account {
    var cloudStorage:CloudStorage? {
#if DEBUG
        if let loadTesting = Configuration.server.loadTestingCloudStorage, loadTesting {
            return MockStorage()
        }
        else {
            return self as? CloudStorage
        }
#else
        return self as? CloudStorage
#endif
    }
}
```

## Server

1. Check for valid credentials for file virtual owner.
[MOVED TO ISSUES: https://github.com/SyncServerII/ServerMain/issues/1] 

Internally, in my server, I need a means to check if credentials are valid under the following scenario: User A tries to access the files of user B. E.g., user A tries to download one of user B’s files. 

If B is an owning user the final/authoritative check will be made by the owning cloud service, and will be terminated there if B’s credentials are invalid or have been revoked. 

If B is a sharing user the situation seems more complicated. The file can be virtually owned by user B (i.e., B initiated the upload), but really owned by say owning user C—where C is a real owning user. In this case, we need to do what we can to make sure that B’s credentials are valid before allowing the download. It doesn’t seem to make sense to allow a download for a file when its (virtual) owner is invalid. For Apple Sign In credentials, we may need to make a 24 hour validity check with Apple if that call hasn’t been made in the last 24 hours. We may also need to check some field in our Apple Sign In credentials (in our custom server database) to see if the credentials are known to be invalid—which could have occurred by Mechanism 2 (see my second Apple Sign In Medium article). This suggests we need an alteration to our Account interface (in https://github.com/SyncServerII/ServerAccount.git) that enables a synchronous check to credentials to see if they are valid or not.

The above also suggests that for our ServerFacebookAccount, we need a polling mechanism to check if the credentials are valid. This is different than the existing generateTokens call for ServerFacebookAccount. The check for valid credentials is not trying to generate tokens, but rather just needing to check if the credentials have been revoked.

2. [DONE] I've removed DoneUploads-- and need functionality for both of the below now.
    [DONE] // Optionally perform a sharing group update-- i.e., change the sharing group's name as part of DoneUploads.
    public var sharingGroupName: String?
    
    [DONE] // Optionally, send a push notification to all members of the sharing group (except for the sender) on a successful DoneUploads. The text of a message for a push notification is application specific and so needs to come from the client.
    public var pushNotificationMessage: String?

    sendNotifications(fromUser: params.currentSignedInUser!, forSharingGroupUUID: sharingGroupUUID, message: pushNotificationMessage!, params: params) { success in
        if success {
            successResponse()
        }
        else {
            let message = "Failed on sendNotifications in finishDoneUploads"
            Log.error(message)
            params.completion(.failure(.message(message)))
        }
        
        async.done()
    }
    
    // Returns true iff success.
    private func sendNotifications(fromUser: User, forSharingGroupUUID sharingGroupUUID: String, message: String, params:RequestProcessingParameters, completion: @escaping (_ success: Bool)->()) {

        guard var users:[User] = params.repos.sharingGroupUser.sharingGroupUsers(forSharingGroupUUID: sharingGroupUUID) else {
            Log.error(("sendNotifications: Failed to get sharing group users!"))
            completion(false)
            return
        }
        
        // Remove sending user from users. They already know they uploaded/deleted-- no point in sending them a notification.
        // Also remove any users that don't have topics-- i.e., they don't have any devices registered for push notifications.
        users = users.filter { user in
            user.userId != fromUser.userId && user.pushNotificationTopic != nil
        }
        
        let key = SharingGroupRepository.LookupKey.sharingGroupUUID(sharingGroupUUID)
        let sharingGroupResult = params.repos.sharingGroup.lookup(key: key, modelInit: SharingGroup.init)
        var sharingGroup: SharingGroup!
        
        switch sharingGroupResult {
        case .found(let model):
            sharingGroup = (model as! SharingGroup)
        case .error(let error):
            Log.error("sendNotifications: \(error)")
            completion(false)
            return
        case .noObjectFound:
            Log.error("sendNotifications: No object found!")
            completion(false)
            return
        }
        
        var modifiedMessage = "\(fromUser.username!)"
        
        if let name = sharingGroup.sharingGroupName {
            modifiedMessage += ", \(name)"
        }
        
        modifiedMessage += ": " + message
        
        guard let formattedMessage = PushNotifications.format(message: modifiedMessage) else {
            Log.error("sendNotifications: Failed on formatting message.")
            completion(false)
            return
        }
        
        guard let pn = PushNotifications() else {
            Log.error("sendNotifications: Failed on PushNotifications constructor.")
            completion(false)
            return
        }
        
        pn.send(formattedMessage: formattedMessage, toUsers: users, completion: completion)
    }

[DONE] 3. Need to re-work UploadDeletion.

[DONE] 4. Need to add sharing group renaming back in.


        // See if we have to do a sharing group update operation.
        if let sharingGroupName = sharingGroupName {
            let serverSharingGroup = Server.SharingGroup()
            serverSharingGroup.sharingGroupUUID = sharingGroupUUID
            serverSharingGroup.sharingGroupName = sharingGroupName

            if !params.repos.sharingGroup.update(sharingGroup: serverSharingGroup) {
                let message = "Failed in updating sharing group."
                Log.error(message)
                return .error(.failure(.message(message)))
            }
        }
