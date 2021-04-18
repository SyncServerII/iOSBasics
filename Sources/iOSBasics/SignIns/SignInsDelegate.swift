import Foundation
import iOSSignIn
import ServerShared

/// These operations are with respect to the SyncServer and it's network API, and not specifically about the UI or the specific sign-ins (e.g., Dropbox, Facebook).
public protocol SignInsDelegate: AnyObject {
    // Called after a successful `checkCreds` server request. The user is known to have an account on the server.
    func signInCompleted(_ signIns: SignIns, userInfo: CheckCredsResponse.UserInfo)
    
    // Called after a successful `addUser` server request. A new owning user has been created on the server.
    func newOwningUserCreated(_ signIns: SignIns)
    
    // Called after a successful `redeemSharingInvitation` server request.
    func invitationAccepted(_ signIns: SignIns, redeemResult: RedeemResult)
    
    // Called in various circumstances where the user must be signed out.
    func userIsSignedOut(_ signIns: SignIns)
    
    func setCredentials(_ signIns: SignIns, credentials: GenericCredentials?)
}
