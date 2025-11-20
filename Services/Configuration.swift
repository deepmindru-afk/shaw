//
//  Configuration.swift
//  AI Voice Copilot
//

import Foundation

enum AppEnvironment {
    case development
    case staging
    case production

    static var current: AppEnvironment {
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }
}

struct Configuration {
    static let shared = Configuration()

    private init() {}

    var apiBaseURL: String {
        switch AppEnvironment.current {
        case .development:
            return ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://roadtrip.up.railway.app/v1"
        case .staging:
            return ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://roadtrip.up.railway.app/v1"
        case .production:
            return ProcessInfo.processInfo.environment["API_BASE_URL"] ?? "https://roadtrip.up.railway.app/v1"
        }
    }

    var authLoginURL: String {
        return "\(apiBaseURL)/auth/login"
    }

    var authRefreshURL: String {
        return "\(apiBaseURL)/auth/refresh"
    }

    var isLoggingEnabled: Bool {
        switch AppEnvironment.current {
        case .development:
            return true
        case .staging:
            return true
        case .production:
            return UserSettings.shared.loggingEnabled
        }
    }

    func printConfiguration() {
        print("""
        ================================================
        AI Voice Copilot Configuration
        ================================================
        Environment: \(AppEnvironment.current)
        API Base URL: \(apiBaseURL)
        Auth Login URL: \(authLoginURL)
        Logging Enabled: \(isLoggingEnabled)
        ================================================
        """)
    }
}
