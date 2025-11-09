//
//  SessionLoggerTests.swift
//  AI Voice Copilot Tests
//

import XCTest
@testable import CarPlaySwiftUI

final class SessionLoggerTests: XCTestCase {
    var sessionLogger: SessionLogger!
    var urlSession: URLSession!
    
    override func setUp() {
        super.setUp()
        
        // Configure URLSession with mock protocol
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        urlSession = URLSession(configuration: config)
        
        // Create SessionLogger with mock URLSession
        sessionLogger = SessionLogger(urlSession: urlSession)
    }
    
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        sessionLogger = nil
        urlSession = nil
        super.tearDown()
    }
    
    func testStartSessionRequestStructure() async throws {
        // Given
        let context: Session.SessionContext = .phone
        let expectedSessionId = "test-session-id"
        let expectedUrl = "wss://livekit.example.com"
        let expectedToken = "test-token"
        let expectedRoom = "test-room"
        
        MockURLProtocol.requestHandler = { request in
            // Assert request structure
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/sessions/start")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "Content-Type"))
            
            // Assert request body
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            XCTAssertEqual(body["context"] as? String, "phone")
            
            // Return mock response
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            
            let responseData = """
            {
                "session_id": "\(expectedSessionId)",
                "livekit_url": "\(expectedUrl)",
                "livekit_token": "\(expectedToken)",
                "room_name": "\(expectedRoom)"
            }
            """.data(using: .utf8)!
            
            return (response, responseData)
        }
        
        // When
        let response = try await sessionLogger.startSession(context: context)
        
        // Then
        XCTAssertEqual(response.sessionId, expectedSessionId)
        XCTAssertEqual(response.livekitUrl, expectedUrl)
        XCTAssertEqual(response.livekitToken, expectedToken)
        XCTAssertEqual(response.roomName, expectedRoom)
    }
    
    func testStartSessionWithAuthToken() async throws {
        // Given
        AuthService.shared.setToken("test-token")
        let context: Session.SessionContext = .phone
        
        MockURLProtocol.requestHandler = { request in
            // Assert Authorization header is present
            let authHeader = request.value(forHTTPHeaderField: "Authorization")
            XCTAssertEqual(authHeader, "Bearer test-token")
            
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            
            let responseData = """
            {
                "session_id": "test-id",
                "livekit_url": "wss://test.com",
                "livekit_token": "token",
                "room_name": "room"
            }
            """.data(using: .utf8)!
            
            return (response, responseData)
        }
        
        // When/Then - should not throw
        _ = try await sessionLogger.startSession(context: context)
        
        // Cleanup
        AuthService.shared.logout()
    }
    
    func testEndSessionHandlesEmptyResponse() async throws {
        // Given
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/sessions/end")
            
            // Return 204 No Content (empty body)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 204,
                httpVersion: nil,
                headerFields: [:]
            )!
            
            return (response, Data())
        }
        
        // When/Then - should not throw
        try await sessionLogger.endSession(sessionID: "test-id")
    }
    
    func testLogTurnRespectsLoggingEnabled() {
        // Given
        let settings = UserSettings.shared
        let originalValue = settings.loggingEnabled
        
        var requestMade = false
        MockURLProtocol.requestHandler = { _ in
            requestMade = true
            let response = HTTPURLResponse(
                url: URL(string: "https://test.com")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [:]
            )!
            return (response, Data())
        }
        
        // When logging disabled
        settings.loggingEnabled = false
        sessionLogger.logTurn(
            sessionID: "test-id",
            speaker: .user,
            text: "Test",
            timestamp: Date()
        )
        
        // Give it a moment to potentially make the request
        Thread.sleep(forTimeInterval: 0.1)
        
        // Then - should not make network call
        XCTAssertFalse(requestMade)
        
        // Restore
        settings.loggingEnabled = originalValue
    }
    
    func testFetchSessionsRequestStructure() async throws {
        // Given
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/sessions")
            
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            
            let responseData = """
            [
                {
                    "id": "session-1",
                    "title": "Test Session",
                    "summary_snippet": "Test summary",
                    "started_at": "2024-01-01T00:00:00Z",
                    "ended_at": "2024-01-01T01:00:00Z"
                }
            ]
            """.data(using: .utf8)!
            
            return (response, responseData)
        }
        
        // When
        let sessions = try await sessionLogger.fetchSessions()
        
        // Then
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, "session-1")
        XCTAssertEqual(sessions.first?.title, "Test Session")
    }
    
    func testDeleteSessionHandlesEmptyResponse() async throws {
        // Given
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/v1/sessions/test-id")
            
            // Return 204 No Content
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 204,
                httpVersion: nil,
                headerFields: [:]
            )!
            
            return (response, Data())
        }
        
        // When/Then - should not throw
        try await sessionLogger.deleteSession(sessionID: "test-id")
    }
}

