import Foundation
import iOSSignIn

public protocol SignInsDelegate: AnyObject {
    // Using AnyObject instead of SignIns because SignIns is an internal type.
    func signInCompleted(_ signIns: AnyObject)
    func newOwningUserCreated(_ signIns: AnyObject)
    func invitationAcceptedAndUserCreated(_ signIns: AnyObject)
    func userIsSignedOut(_ signIns: AnyObject)
    func setCredentials(_ signIns: AnyObject, credentials: GenericCredentials?)
}
