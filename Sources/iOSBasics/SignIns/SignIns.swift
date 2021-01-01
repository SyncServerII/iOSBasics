import Foundation
import iOSSignIn
import iOSShared
import ServerShared
import Logging

// The integration point between iOSSignIn and iOSBasics with respect to sign-in's.

public class SignIns {
    enum SignInsError: Error {
        case noSignedInUser
    }
    
    weak var signInServicesHelper:SignInServicesHelper!
    public weak var delegate:SignInsDelegate!
    var api:ServerAPI!
    var cloudFolderName:String?
    
    // For SyncServer delegate calls
    var delegator: ((@escaping (SyncServerDelegate)->())->())!
    weak var syncServer:SyncServer!
    
    public init(signInServicesHelper: SignInServicesHelper) {
        self.signInServicesHelper = signInServicesHelper
    }
    
    #warning("TODO: This is being reported as an error. But it's not always used as an error. Plus, these just aren't showing up in Neebla yet.")
    #warning("I think what needs to happen here is that the `error` delegate needs to change to something like `userAlert`")
    private func showAlert(withTitle title: String, message: String) {
        delegator { [weak self] delegate in
            guard let self = self else { return }
            delegate.userEvent(self.syncServer, event: .showAlert(title: title, message: message))
        }
    }

    func completeSignInProcess(accountMode: AccountMode, autoSignIn:Bool) {
        guard let credentials = signInServicesHelper.currentCredentials,
            let userType = signInServicesHelper.userType else {
            signUserOut()
            showAlert(withTitle: "Alert!", message: "Oh, yikes. Something bad has happened.")
            return
        }

        // We're about to use the API-- setup its credentials. If we have a failure, we'll sign the user out, and reset this.
        delegate?.setCredentials(self, credentials: credentials)
        
        switch accountMode {
        case .signIn:
            api.checkCreds(credentials) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let result):
                    switch result {
                    case .noUser:
                        self.signUserOut()
                        self.showAlert(withTitle: "Alert!", message: "User not found on system.")
                        logger.info("signUserOut: noUser in checkForExistingUser")

                    case .user(userId: let userId, accessToken: let accessToken):
                        logger.info("SyncServer user signed in: access token: \(String(describing: accessToken))")
                        self.delegate?.signInCompleted(self, userId: userId)
                    }
                    
                case .failure(let error):
                    logger.error("\(error)")
                    let message:Logger.Message = "Error checking for existing user on server."
                    logger.error(message)
                    
                    // 10/22/17; It doesn't seem legit to sign user out if we're doing this during a launch sign-in. That is, the user was signed in last time the app launched. And this is a generic error (e.g., a network error). However, if we're not doing this during app launch, i.e., this is a sign-in request explicitly by the user, if that fails it means we're not already signed-in, so it's safe to force the sign out.
                    
                    if !autoSignIn {
                        self.signUserOut()
                        logger.error("signUserOut: error in checkForExistingUser and not autoSignIn")
                        self.showAlert(withTitle: "Alert!", message: message.description)
                    }
                }
            }
            
        case .createOwningUser:
            if userType == .sharing {
                // 10/22/17; Seems legit. Very odd error situation.
                self.signUserOut()
                 // Social users cannot be owning users! They don't have cloud storage.
                showAlert(withTitle: "Alert!", message: "Somehow a sharing user attempted to create an owning user!!")
                logger.error("signUserOut: sharing user tried to create an owning user!")
            }
            else {
                // We should always have non-nil credentials here. We'll get to here only in the non-autosign-in case (explicit request from user to create an account). In which case, we must have credentials.

                let sharingGroupUUID = UUID()
                api.addUser(cloudFolderName: cloudFolderName, sharingGroupUUID: sharingGroupUUID, sharingGroupName: nil) { [weak self] result in
                    guard let self = self else { return }
                    switch result {
                    case .failure(let error):
                        // 10/22/17; User is signing up. I.e., they don't have an account. Seems OK to sign them out.
                        self.signUserOut()
                        self.showAlert(withTitle: "Alert!", message: "Error creating owning user.")
                        logger.error("Error creating owning user: \(error)")
                        
                    case .success(let addUserResult):
                        switch addUserResult {
                        case .userId:
                            self.delegate?.newOwningUserCreated(self)
                            
                        case .userAlreadyExisted:
                            self.signUserOut()
                            self.showAlert(withTitle: "Alert!", message: "That account has already been created: Please use the sign-in option.")
                        }
                    }
                }
            }
            
        case .acceptInvitationAndCreateUser(invitation: let invitation):
            guard let codeUUID = UUID(uuidString: invitation.code) else {
                self.signUserOut()
                let message = "Invitation was invalid."
                self.showAlert(withTitle: "Alert!", message: message)
                return
            }
            
            api.redeemSharingInvitation(sharingInvitationUUID: codeUUID, cloudFolderName: cloudFolderName) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .failure(let error):
                    // 10/22/17; The common situation here seems to be the user is signing up via a sharing invitation. They are not on the system yet in that case. Seems safe to sign them out.
                    self.signUserOut()
                    let message = "Error creating sharing user."
                    self.showAlert(withTitle: "Alert!", message: message)
                    logger.error("signUserOut: Error in redeemSharingInvitation: \(error)")
                    
                case .success(let result):
                    logger.info("Access token: \(String(describing: result.accessToken))")
                    self.delegate?.invitationAcceptedAndUserCreated(self)
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

// The `iOSSignIn.SignInsDelegate` and `SyncServerCredentials` conformances are critical to integration between iOSSignIn and iOSBasics.

extension SignIns: iOSSignIn.SignInsDelegate {
    public func signInCompleted(_ manager: SignInManager, signIn: GenericSignIn,  mode: AccountMode, autoSignIn: Bool) {
        completeSignInProcess(accountMode: mode, autoSignIn: autoSignIn)
    }
    
    public func userIsSignedOut(_ manager: SignInManager, signIn: GenericSignIn) {
        delegate?.setCredentials(self, credentials: nil)
    }
}

extension SignIns: SyncServerCredentials {
    public func credentialsForServerRequests(_ syncServer: SyncServer) throws -> GenericCredentials {
        if let credentials = signInServicesHelper.currentCredentials {
            return credentials
        }
        throw SignInsError.noSignedInUser
    }
}
