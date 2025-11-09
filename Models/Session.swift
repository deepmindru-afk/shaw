//
//  Session.swift
//  AI Voice Copilot
//

import Foundation

struct Session: Identifiable, Codable {
    let id: String
    let userId: String
    let context: SessionContext
    let startedAt: Date
    var endedAt: Date?
    let loggingEnabledSnapshot: Bool
    var summaryStatus: SummaryStatus
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case context
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case loggingEnabledSnapshot = "logging_enabled_snapshot"
        case summaryStatus = "summary_status"
    }
    
    enum SessionContext: String, Codable {
        case carplay
        case phone
    }
    
    enum SummaryStatus: String, Codable {
        case pending
        case ready
        case failed
    }
}

struct SessionSummary: Codable {
    let id: String
    let sessionId: String
    let title: String
    let summaryText: String
    let actionItems: [String]
    let tags: [String]
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case title
        case summaryText = "summary_text"
        case actionItems = "action_items"
        case tags
        case createdAt = "created_at"
    }
}

struct Turn: Identifiable, Codable {
    let id: String
    let sessionId: String
    let timestamp: Date
    let speaker: Speaker
    let text: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case timestamp
        case speaker
        case text
    }
    
    enum Speaker: String, Codable {
        case user
        case assistant
    }
}

struct SessionListItem: Identifiable, Codable {
    let id: String
    let title: String
    let summarySnippet: String
    let startedAt: Date
    let endedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summarySnippet = "summary_snippet"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }
}

struct StartSessionResponse: Codable {
    let sessionId: String
    let livekitUrl: String
    let livekitToken: String
    let roomName: String
    
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case livekitUrl = "livekit_url"
        case livekitToken = "livekit_token"
        case roomName = "room_name"
    }
}

