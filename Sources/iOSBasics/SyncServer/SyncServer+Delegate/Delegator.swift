
import Foundation

// Calls SyncServerDelegate methods on the `delegateDispatchQueue` either synchronously or asynchronously.
class Delegator {
    private weak var delegate: SyncServerDelegate!
    private let delegateDispatchQueue: DispatchQueue
    
    init(delegate: SyncServerDelegate, delegateDispatchQueue: DispatchQueue) {
        self.delegate = delegate
        self.delegateDispatchQueue = delegateDispatchQueue
    }
    
    // All delegate methods must be called using this, to have them called on the client requested DispatchQueue. Delegate methods are called asynchronously on the `delegateDispatchQueue`.
    // (Not doing sync here because need to resolve issue: https://stackoverflow.com/questions/63784355)
    func call(callback: @escaping (SyncServerDelegate)->()) {
        delegateDispatchQueue.async { [weak self] in
            guard let self = self else { return }
            callback(self.delegate)
        }
    }
}
