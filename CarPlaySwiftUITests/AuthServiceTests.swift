//
//  AuthServiceTests.swift
//  AI Voice Copilot Tests
//

import XCTest
@testable import CarPlaySwiftUI

final class AuthServiceTests: XCTestCase {
    var authService: AuthService!
    
    override func setUp() {
        super.setUp()
        authService = AuthService.shared
        // Clear any existing token
        authService.authToken = nil
    }
    
    override func tearDown() {
        authService.authToken = nil
        super.tearDown()
    }
    
    func testTokenStorage() {
        // Given
        let testToken = "test_token_123"
        
        // When
        authService.authToken = testToken
        
        // Then
        XCTAssertEqual(authService.authToken, testToken)
        XCTAssertTrue(authService.isAuthenticated)
    }
    
    func testTokenDeletion() {
        // Given
        authService.authToken = "test_token"
        
        // When
        authService.authToken = nil
        
        // Then
        XCTAssertNil(authService.authToken)
        XCTAssertFalse(authService.isAuthenticated)
    }
    
    func testIsAuthenticatedWithoutToken() {
        // Given
        authService.authToken = nil
        
        // Then
        XCTAssertFalse(authService.isAuthenticated)
    }
}

