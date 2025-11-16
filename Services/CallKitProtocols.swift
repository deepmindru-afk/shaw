//
//  CallKitProtocols.swift
//  AI Voice Copilot
//

import Foundation
import CallKit

// MARK: - Protocols for Dependency Injection

protocol CXProviderProtocol {
    func setDelegate(_ delegate: CXProviderDelegate?, queue: DispatchQueue?)
    func reportOutgoingCall(with callUUID: UUID, startedConnectingAt dateStartedConnecting: Date?)
    func reportOutgoingCall(with callUUID: UUID, connectedAt dateConnected: Date?)
}

protocol CXCallControllerProtocol {
    func request(_ transaction: CXTransaction, completion: @escaping @Sendable (Error?) -> Void)
}

// MARK: - Wrappers for Production Use

extension CXProvider: CXProviderProtocol {
    // CXProvider already conforms, no additional implementation needed
}

extension CXCallController: CXCallControllerProtocol {
    // CXCallController already conforms, no additional implementation needed
}

