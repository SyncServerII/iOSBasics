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
    
    private func showAlert(withTitle title: String, message: String) {
        delegator { [weak self] delegate in
            guard let self = self else { return }
            delegate.userEvent(self.syncServer, event: .showAlert(title: title, message: message))
        }
    }

    func completeSignInProcess(accountMode: AccountMode, autoSignIn:Bool) {
        guard let credentials = signInServicesHelper.currentCredentials,
            let userType = signInServicesHelper.userType else {
            signUserOut(logMessage: "Failed completeSignInProcess")
            showAlert(withTitle: "Alert!", message: "Oh, yikes. Something bad has happened.")
            return
        }
        
        switch accountMode {
        case .signIn:
            api.checkCreds(emailAddress: credentials.emailAddress) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let result):
                    switch result {
                    case .noUser:
                        self.signUserOut(logMessage: "signUserOut: noUser in checkForExistingUser")
                        self.showAlert(withTitle: "Alert!", message: "User not found on system.")

                    case .user(userInfo: let userInfo, accessToken: let accessToken):
                        logger.info("SyncServer user signed in: access token: \(String(describing: accessToken)); userInfo: \(userInfo)")
                        self.delegate?.signInCompleted(self, userInfo: userInfo)
                    }
                    
                case .failure(let error):
                    logger.error("\(error)")
                    let message:Logger.Message = "Error checking for existing user on server."
                    logger.error(message)
                    
                    // 10/22/17; It doesn't seem legit to sign user out if we're doing this during a launch sign-in. That is, the user was signed in last time the app launched. And this is a generic error (e.g., a network error). However, if we're not doing this during app launch, i.e., this is a sign-in request explicitly by the user, if that fails it means we're not already signed-in, so it's safe to force the sign out.
                    
                    if !autoSignIn {
                        self.signUserOut(logMessage: "signUserOut: error in checkForExistingUser and not autoSignIn")
                        self.showAlert(withTitle: "Alert!", message: message.description)
                    }
                }
            }
            
        case .createOwningUser:
            if userType == .sharing {
                // 10/22/17; Seems legit. Very odd error situation.
                self.signUserOut(logMessage: "signUserOut: sharing user tried to create an owning user!")
                 // Social users cannot be owning users! They don't have cloud storage.
                showAlert(withTitle: "Alert!", message: "Somehow a sharing user attempted to create an owning user!!")
            }
            else {
                // We should always have non-nil credentials here. We'll get to here only in the non-autosign-in case (explicit request from user to create an account). In which case, we must have credentials.

                let sharingGroupUUID = UUID()
                api.addUser(cloudFolderName: cloudFolderName, emailAddress: credentials.emailAddress, sharingGroupUUID: sharingGroupUUID, sharingGroupName: nil) { [weak self] result in
                    guard let self = self else { return }
                    switch result {
                    case .failure(let error):
                        // 10/22/17; User is signing up. I.e., they don't have an account. Seems OK to sign them out.
                        self.signUserOut(logMessage: "Error creating owning user: \(error)")
                        self.showAlert(withTitle: "Alert!", message: "Error creating owning user.")
                        
                    case .success(let addUserResult):
                        switch addUserResult {
                        case .userId:
                            self.delegate?.newOwningUserCreated(self)
                            
                        case .userAlreadyExisted:
                            self.signUserOut(logMessage: "Success but userAlreadyExisted")
                            self.showAlert(withTitle: "Alert!", message: "That account has already been created: Please use the sign-in option.")
                        }
                    }
                }
            }
            
        case .acceptInvitation(invitation: let invitation):
            guard let codeUUID = UUID(uuidString: invitation.code) else {
                self.signUserOut(logMessage: "acceptInvitation worked, but bad codeUUID")
                let message = "Invitation was invalid."
                self.showAlert(withTitle: "Alert!", message: message)
                return
            }
            
            api.redeemSharingInvitation(sharingInvitationUUID: codeUUID, cloudFolderName: cloudFolderName) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .failure(let error):
                    // 10/22/17; The common situation here seems to be the user is signing up via a sharing invitation. They are not on the system yet in that case. Seems safe to sign them out.
                    self.signUserOut(logMessage: "signUserOut: Error in redeemSharingInvitation: \(error)")
                    let message = "Error creating sharing user."
                    self.showAlert(withTitle: "Alert!", message: message)
                    
                case .success(let result):
                    logger.info("Access token: \(String(describing: result.accessToken))")
                    self.delegate?.invitationAccepted(self, redeemResult: result)
                }
            }
        }
    }
    
    private func signUserOut(logMessage: String? = nil) {
        if let logMessage = logMessage {
            logger.error("signUserOut: \(logMessage)")
        }
        signInServicesHelper.signUserOut()
        self.delegate?.userIsSignedOut(self)
    }
    
    /// Update the user's userName
    public func updateUser(userName: String, completion: @escaping (Error?) -> ()) {
        api.serialQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.api.updateUser(userName: userName) { error in
                DispatchQueue.main.async {
                    completion(error)
                }
            }
        }
    }
    
    /// Remove the current signed in user from the system. If there was no error, then the current user is also signed out after this call.
    public func removeUser(completion: @escaping (Error?) -> ()) {
        api.serialQueue.async { [weak self] in
            guard let self = self else { return }

            self.api.removeUser { [weak self] error in
                guard let self = self else { return }
                
                if error == nil {
                    self.signUserOut()
                }
                
                DispatchQueue.main.async {
                    completion(error)
                }
            }
        }
    }
}

// The `iOSSignIn.SignInsDelegate` and `SyncServerCredentials` conformances are critical to integration between iOSSignIn and iOSBasics.

extension SignIns: iOSSignIn.SignInsDelegate {
    public func signInCompleted(_ manager: SignInManager, signIn: GenericSignIn,  mode: AccountMode, autoSignIn: Bool) {
        api.serialQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.completeSignInProcess(accountMode: mode, autoSignIn: autoSignIn)
        }
    }
    
    public func userIsSignedOut(_ manager: SignInManager, signIn: GenericSignIn) {
        delegate?.userIsSignedOut(self)
    }
}

extension SignIns: SyncServerCredentials {
    public func credentialsForServerRequests(_ syncServer: SyncServer) throws -> GenericCredentials {
        guard let credentials = signInServicesHelper.currentCredentials else {
            throw SignInsError.noSignedInUser
        }
        
        return credentials
    }
}
