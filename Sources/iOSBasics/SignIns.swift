import iOSSignIn

public class SignIns {
    let services:SignInServices
    
    public init(services:SignInServices) {
        self.services = services
    }
}

extension SignIns: SignInManagerDelegate {
    public func signInCompleted(_ manager: SignInManager, signIn: GenericSignIn) {
        
    }
    
    public func userIsSignedOut(_ manager: SignInManager, signIn: GenericSignIn) {
        
    }
}
