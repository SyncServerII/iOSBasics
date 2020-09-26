import Foundation
import iOSSignIn

#warning("Some functionality seems duplicated across this and SignInManagerDelegate")
// signInCompleted-- seems duplicated. As does userIsSignedOut. And what is setCredentials about?

/// These operations are with respect to the SyncServer and it's network API, and not specifically about the UI or the specific sign-ins (e.g., Dropbox, Facebook).
protocol SignInsDelegate: AnyObject {
    // Using AnyObject instead of SignIns because SignIns is an internal type.
    
    // Called after a successful `checkCreds` server request. The user is known to have an account on the server.
    func signInCompleted(_ signIns: AnyObject)
    
    // Called after a successful `addUser` server request. A new owning user has been created on the server.
    func newOwningUserCreated(_ signIns: AnyObject)
    
    // Called after a successful `redeemSharingInvitation` server request.
    func invitationAcceptedAndUserCreated(_ signIns: AnyObject)
    
    // Called in various circumstances where the user must be signed out.
    func userIsSignedOut(_ signIns: AnyObject)
    
    func setCredentials(_ signIns: AnyObject, credentials: GenericCredentials?)
}
