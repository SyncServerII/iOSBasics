import Foundation
import iOSSignIn
import iOSShared
import ServerShared
import Logging

public class SignIns {
    enum SignInsError: Error {
        case noSignedInUser
    }
    
    var signInServicesHelper:SignInServicesHelper
    var api:ServerAPI!
    var cloudFolderName:String?
    private weak var delegate:SignInsDelegate!
    private var credentials: GenericCredentials?
    
    public init(signInServicesHelper: SignInServicesHelper) {
        self.signInServicesHelper = signInServicesHelper
    }

    func completeSignInProcess(accountMode: AccountMode, autoSignIn:Bool) {
        guard let credentials = signInServicesHelper.currentCredentials,
            let userType = signInServicesHelper.userType else {
            signUserOut()
            Alert.show(withTitle: "Alert!", message: "Oh, yikes. Something bad has happened.")
            return
        }

        // We're about to use the API-- setup its credentials. If we have a failure, we'll sign the user out, and reset this.
        #warning("Seems odd to call this delegate method, if we can have a failure, if it's a user delegate call.")
        delegate?.setCredentials(self, credentials: credentials)
        
        switch accountMode {
        case .signIn:
            api.checkCreds(credentials) { [unowned self] result in
                switch result {
                case .success(let result):
                    switch result {
                    case .noUser:
                        Alert.show(withTitle: "Alert!", message: "User not found on system.")
                        logger.info("signUserOut: noUser in checkForExistingUser")
                        self.signUserOut()
                        
                    case .user(accessToken: let accessToken):
                        logger.info("Sharing user signed in: access token: \(String(describing: accessToken))")
                        self.delegate?.signInCompleted(self)
                    }
                    
                case .failure(let error):
                    let message:Logger.Message = "Error checking for existing user: \(error)"
                    logger.error(message)
                    
                    // 10/22/17; It doesn't seem legit to sign user out if we're doing this during a launch sign-in. That is, the user was signed in last time the app launched. And this is a generic error (e.g., a network error). However, if we're not doing this during app launch, i.e., this is a sign-in request explicitly by the user, if that fails it means we're not already signed-in, so it's safe to force the sign out.
                    
                    if !autoSignIn {
                        self.signUserOut()
                        logger.error("signUserOut: error in checkForExistingUser and not autoSignIn")
                        Alert.show(withTitle: "Alert!", message: message.description)
                    }
                }
            }
            
        case .createOwningUser:
            if userType == .sharing {
                 // Social users cannot be owning users! They don't have cloud storage.
                Alert.show(withTitle: "Alert!", message: "Somehow a sharing user attempted to create an owning user!!")
                // 10/22/17; Seems legit. Very odd error situation.
                self.signUserOut()
                logger.error("signUserOut: sharing user tried to create an owning user!")
            }
            else {
                // We should always have non-nil credentials here. We'll get to here only in the non-autosign-in case (explicit request from user to create an account). In which case, we must have credentials.

                let sharingGroupUUID = UUID()
                api.addUser(cloudFolderName: cloudFolderName, sharingGroupUUID: sharingGroupUUID, sharingGroupName: nil) { result in
                    switch result {
                    case .failure(let error):
                        // 10/22/17; User is signing up. I.e., they don't have an account. Seems OK to sign them out.
                        self.signUserOut()
                        Alert.show(withTitle: "Alert!", message: "Error creating owning user: \(error)")
                        
                    case .success:
                        self.delegate?.newOwningUserCreated(self)
                        Alert.show(withTitle: "Success!", message: "Created new owning user! You are now signed in too!")
                    }
                }
            }
            
        case .acceptInvitationAndCreateUser(invitation: let invitation):
            api.redeemSharingInvitation(sharingInvitationUUID: invitation.code, cloudFolderName: cloudFolderName) { result in
                switch result {
                case .failure(let error):
                    logger.error("Error: \(String(describing: error))")
                    Alert.show(withTitle: "Alert!", message: "Error creating sharing user: \(String(describing: error))")
                    // 10/22/17; The common situation here seems to be the user is signing up via a sharing invitation. They are not on the system yet in that case. Seems safe to sign them out.
                    self.signUserOut()
                    logger.error("signUserOut: Error in redeemSharingInvitation in")
                    
                case .success(let result):
                    logger.info("Access token: \(String(describing: result.accessToken))")
                    self.delegate?.invitationAcceptedAndUserCreated(self)
                    Alert.show(withTitle: "Success!", message: "Created new sharing user! You are now signed in too!")
                }
            }
        }
    }
    
    private func signUserOut() {
        signInServicesHelper.signUserOut()
        self.delegate?.userIsSignedOut(self)
        delegate?.setCredentials(self, credentials: nil)
    }
}

extension SignIns: SignInManagerDelegate {
    public func signInCompleted(_ manager: SignInManager, signIn: GenericSignIn,  mode: AccountMode, autoSignIn: Bool) {
        credentials = signIn.credentials

        completeSignInProcess(accountMode: mode, autoSignIn: autoSignIn)
        
        // Reset the invitation, if any, so it doesn't get used again.
        signInServicesHelper.resetCurrentInvitation()
    }
    
    public func userIsSignedOut(_ manager: SignInManager, signIn: GenericSignIn) {
        credentials = nil
        signInServicesHelper.resetCurrentInvitation()
        delegate?.setCredentials(self, credentials: nil)
    }
}

extension SignIns: SyncServerCredentials {
    public func credentialsForServerRequests(_ syncServer: SyncServer) throws -> GenericCredentials {
        if let credentials = credentials {
            return credentials
        }
        throw SignInsError.noSignedInUser
    }
}
