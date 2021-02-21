//
//  Reachability.swift
//  
//
//  Created by Christopher G Prince on 2/20/21.
//

// See https://www.hackingwithswift.com/example-code/networking/how-to-check-for-internet-connectivity-using-nwpathmonitor
// And https://medium.com/@rwbutler/nwpathmonitor-the-new-reachability-de101a5a8835

import Foundation
import iOSShared
import Hyperconnectivity
import Combine

class Reachability: ObservableObject {
    @Published private(set) var isReachable: Bool = false
    private var cancellable: AnyCancellable!
    
    init() {
        // See also https://stackoverflow.com/questions/27500940
#if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            isReachable = true
            return
        }
#endif

        cancellable = Hyperconnectivity.Publisher()
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
            .sink(receiveValue: { [weak self] connectivityResult in
                self?.isReachable = connectivityResult.isConnected
                logger.debug("isReachable: \(String(describing: self?.isReachable))")
            })
    }
}
