//
//  SyncServer+Deferred.swift
//  
//
//  Created by Christopher G Prince on 2/25/21.
//

import Foundation
import iOSShared

extension SyncServer {
    func checkOnDeferred(completion: (()->())? = nil) {
        DispatchQueue.global().async {
            do {
                try self.checkOnDeferredHelper()
            } catch let error {
                self.delegator { [weak self] delegate in
                    guard let self = self else { return }
                    delegate.userEvent(self, event: .error(error))
                }
            }
            
            completion?()
        }
    }
    
    // In this, `checkOnDeferredUploads` and `checkOnDeferredDeletions` do networking calls *synchronously*. This can block the caller for a long period of time.
    private func checkOnDeferredHelper() throws {
        let fileGroupUUIDs1 = try checkOnDeferredUploads()
        logger.debug("checkOnDeferredUploads: fileGroupUUIDs1: \(fileGroupUUIDs1)")
        
        if fileGroupUUIDs1.count > 0 {
            delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.deferredCompleted(self, operation: .upload, fileGroupUUIDs: fileGroupUUIDs1)
            }
        }
        
        let fileGroupUUIDs2 = try checkOnDeferredDeletions()
        if fileGroupUUIDs2.count > 0 {
            delegator { [weak self] delegate in
                guard let self = self else { return }
                delegate.deferredCompleted(self, operation: .deletion, fileGroupUUIDs: fileGroupUUIDs2)
            }
        }
        
        // Check if there are more vN uploads waiting for deferred operations to complete.
        let vNCompletedUploads = try serialQueue.sync {
            return try deferredUploadsWaiting()
        }
        
        logger.debug("vNCompletedUploads: \(vNCompletedUploads)")

        if vNCompletedUploads.count > 0 {
            startTimedDeferredCheckIfNeeded()
        }
        else {
            stopTimedDeferredCheckIfNeeded()
        }
    }
        
    // Start timed check if there's not one running already.
    func startTimedDeferredCheckIfNeeded() {
        serialQueue.async { [weak self] in
            guard let self = self else { return }
            
            guard self.deferredOperationTimer == nil else {
                return
            }
            
            logger.debug("deferredOperationTimer: Creating timer")
                        
            // `Timer.scheduledTimer` on the `serialQueue` doesn't work. Presumably that queue doesn't have a run loop.
            let timer = Timer(timeInterval: self.configuration.deferredCheckInterval, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                
                logger.debug("deferredOperationTimer: Running")
                
                // First, set timer to nil so we can restart it later.
                self.deferredOperationTimer = nil

                self.checkOnDeferred()
            }
            
            DispatchQueue.main.async {
                RunLoop.current.add(timer, forMode: RunLoop.Mode.common)
            }
            
            self.deferredOperationTimer = timer
        }
    }
    
    private func stopTimedDeferredCheckIfNeeded() {
        serialQueue.async { [weak self] in
            guard let self = self else { return }

            guard let deferredOperationTimer = self.deferredOperationTimer else {
                return
            }
            
            deferredOperationTimer.invalidate()
            self.deferredOperationTimer = nil
        }
    }
}
