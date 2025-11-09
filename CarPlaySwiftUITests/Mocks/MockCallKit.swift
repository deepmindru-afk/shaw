//
//  MockCallKit.swift
//  AI Voice Copilot Tests
//

import Foundation
import CallKit
import AVFoundation
@testable import CarPlaySwiftUI

// MARK: - Mock CXProvider

class MockCXProvider: NSObject, CXProviderProtocol {
    weak var delegate: CXProviderDelegate?
    var configuration: CXProviderConfiguration
    
    var shouldSucceed = true
    var onStartCall: ((CXStartCallAction) -> Void)?
    var onEndCall: ((CXEndCallAction) -> Void)?
    
    init(configuration: CXProviderConfiguration) {
        self.configuration = configuration
        super.init()
    }
    
    func setDelegate(_ delegate: CXProviderDelegate?, queue: DispatchQueue?) {
        self.delegate = delegate
    }
    
    func reportOutgoingCall(with callUUID: UUID, startedConnectingAt dateStartedConnecting: Date?) {
        // Mock implementation
    }
    
    func reportOutgoingCall(with callUUID: UUID, connectedAt dateConnected: Date?) {
        // Mock implementation
    }
    
    // Simulate provider delegate callbacks
    func simulateStartCallAction(_ action: CXStartCallAction) {
        if shouldSucceed {
            // Configure audio session
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
                try audioSession.setActive(true)
            } catch {
                // Ignore in tests
            }
            
            action.fulfill()
            // Call the delegate method directly
            if let delegate = delegate {
                delegate.provider?(self as! CXProvider, perform: action)
            }
        }
    }
    
    func simulateEndCallAction(_ action: CXEndCallAction) {
        if shouldSucceed {
            // Deactivate audio session
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setActive(false)
            } catch {
                // Ignore in tests
            }
            
            action.fulfill()
            // Call the delegate method directly
            if let delegate = delegate {
                delegate.provider?(self as! CXProvider, perform: action)
            }
        }
    }
}

// MARK: - Mock CXCallController

class MockCXCallController: CXCallControllerProtocol {
    var shouldSucceed = true
    var lastTransaction: CXTransaction?
    var onRequest: ((CXTransaction, @escaping (Error?) -> Void) -> Void)?
    
    func request(_ transaction: CXTransaction, completion: @escaping (Error?) -> Void) {
        lastTransaction = transaction
        
        if let onRequest = onRequest {
            onRequest(transaction, completion)
        } else {
            if shouldSucceed {
                completion(nil)
                
                // Simulate provider delegate callbacks for start/end actions
                if let startAction = transaction.actions.first as? CXStartCallAction {
                    // Trigger delegate callback after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        // This would normally be called by the system
                        // In tests, we'll trigger it manually via the mock provider
                    }
                } else if let endAction = transaction.actions.first as? CXEndCallAction {
                    // Similar for end action
                }
            } else {
                completion(NSError(domain: "MockCallKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Mock error"]))
            }
        }
    }
}

