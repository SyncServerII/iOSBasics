import iOSSignIn
import Foundation
import iOSShared

protocol ServerAPIDelegate: AnyObject {
    func credentialsForNetworkRequests(_ api: AnyObject) -> GenericCredentials
    func deviceUUID(_ api: AnyObject) -> UUID
    func currentHasher(_ api: AnyObject) -> CloudStorageHashing
}
