//
//  AssistantCallCoordinatorTests.swift
//  AI Voice Copilot Tests
//

import XCTest
@testable import CarPlaySwiftUI

@MainActor
final class AssistantCallCoordinatorTests: XCTestCase {
    var coordinator: AssistantCallCoordinator!
    var mockCallManager: CallManager!
    var mockProvider: MockCXProvider!
    var mockCallController: MockCXCallController!
    
    override func setUp() {
        super.setUp()
        
        // Reset singleton
        CallManager.resetShared()
        
        // Create mocks
        let config = CXProviderConfiguration(localizedName: "Test")
        mockProvider = MockCXProvider(configuration: config)
        mockCallController = MockCXCallController()
        mockCallManager = CallManager(provider: mockProvider, callController: mockCallController)
        
        // Create coordinator (it will use CallManager.shared, so we need to ensure it's set)
        // Note: Coordinator uses shared instances, so we test its state transitions
        coordinator = AssistantCallCoordinator.shared
    }
    
    override func tearDown() {
        coordinator = nil
        mockCallManager = nil
        mockProvider = nil
        mockCallController = nil
        CallManager.resetShared()
        super.tearDown()
    }
    
    func testInitialState() {
        // Then
        XCTAssertEqual(coordinator.callState, .idle)
        XCTAssertNil(coordinator.currentSessionID)
        XCTAssertNil(coordinator.errorMessage)
    }
    
    func testStartCallFromPhone() {
        // When
        coordinator.startAssistantCall(context: "phone")
        
        // Then
        XCTAssertEqual(coordinator.callState, .connecting)
    }
    
    func testStartCallFromCarPlay() {
        // When
        coordinator.startAssistantCall(context: "carplay")
        
        // Then
        XCTAssertEqual(coordinator.callState, .connecting)
    }
    
    func testCannotStartCallWhenAlreadyConnecting() {
        // Given
        coordinator.startAssistantCall(context: "phone")
        let initialState = coordinator.callState
        
        // When
        coordinator.startAssistantCall(context: "phone")
        
        // Then
        XCTAssertEqual(coordinator.callState, initialState)
    }
    
    func testEndCallResetsState() {
        // Given
        coordinator.startAssistantCall(context: "phone")
        coordinator.callState = .connected
        coordinator.currentSessionID = "test-session-id"
        
        // When
        coordinator.endAssistantCall()
        
        // Then
        XCTAssertEqual(coordinator.callState, .idle)
        XCTAssertNil(coordinator.currentSessionID)
    }
}

