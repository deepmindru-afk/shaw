//
//  UserSettings.swift
//  AI Voice Copilot
//

import Foundation

class UserSettings: ObservableObject {
    @Published var loggingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(loggingEnabled, forKey: "loggingEnabled")
        }
    }
    
    @Published var retentionDays: Int {
        didSet {
            UserDefaults.standard.set(retentionDays, forKey: "retentionDays")
        }
    }
    
    @Published var hasSeenOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasSeenOnboarding, forKey: "hasSeenOnboarding")
        }
    }
    
    static let shared = UserSettings()
    
    private init() {
        self.loggingEnabled = UserDefaults.standard.bool(forKey: "loggingEnabled")
        self.retentionDays = UserDefaults.standard.integer(forKey: "retentionDays")
        if retentionDays == 0 {
            retentionDays = 30 // Default
        }
        self.hasSeenOnboarding = UserDefaults.standard.bool(forKey: "hasSeenOnboarding")
    }
}

