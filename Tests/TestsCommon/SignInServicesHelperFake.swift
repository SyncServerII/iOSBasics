
import Foundation
import iOSSignIn
import ServerShared

// Integration point stub for iOSSignIn
class SignInServicesHelperFake: SignInServicesHelper {
    var userId: UserId?
    var cloudStorageType: CloudStorageType?
    var currentCredentials: GenericCredentials?
    var userType: UserType?
    var currentSignIn: GenericSignIn?

    init(testUser:TestUser) {
        self.cloudStorageType = testUser.cloudStorageType
    }
    
    func signUserOut() {
    }
    
    func resetCurrentInvitation() {
    }
}
