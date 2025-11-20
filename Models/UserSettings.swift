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

    @Published var isSignedIn: Bool {
        didSet {
            UserDefaults.standard.set(isSignedIn, forKey: "isSignedIn")
        }
    }

    @Published var retentionDays: Int {
        didSet {
            UserDefaults.standard.set(retentionDays, forKey: "retentionDays")
        }
    }

    @Published var selectedModel: AIModel {
        didSet {
            if let data = try? JSONEncoder().encode(selectedModel) {
                UserDefaults.standard.set(data, forKey: "selectedModel")
            }
        }
    }

    @Published var selectedLanguage: VoiceLanguage {
        didSet {
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: "selectedLanguage")
        }
    }

    @Published var selectedVoice: TTSVoice {
        didSet {
            if let data = try? JSONEncoder().encode(selectedVoice) {
                UserDefaults.standard.set(data, forKey: "selectedVoice")
            }
        }
    }

    @Published var toolCallingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(toolCallingEnabled, forKey: "toolCallingEnabled")
            // Skip dependency logic during initialization to preserve user preferences
            guard !isInitializing else { return }
            // Automatically disable web search when tool calling is disabled
            if !toolCallingEnabled {
                self.webSearchEnabled = false
            } else {
                // Automatically enable web search when tool calling is enabled
                self.webSearchEnabled = true
            }
        }
    }

    @Published var webSearchEnabled: Bool {
        didSet {
            UserDefaults.standard.set(webSearchEnabled, forKey: "webSearchEnabled")
        }
    }

    static let shared = UserSettings()

    // Retention options: 0 = Never delete, > 0 = number of days
    
    // Flag to prevent didSet side effects during initialization
    private var isInitializing = true

    private init() {
        self.loggingEnabled = UserDefaults.standard.bool(forKey: "loggingEnabled")
        
        if UserDefaults.standard.object(forKey: "isSignedIn") != nil {
            self.isSignedIn = UserDefaults.standard.bool(forKey: "isSignedIn")
        } else {
            self.isSignedIn = AuthService.shared.appleUserID != nil
        }

        // Check if retentionDays key exists to distinguish between "not set" (default to 30) and "set to 0" (never delete)
        if UserDefaults.standard.object(forKey: "retentionDays") != nil {
            self.retentionDays = UserDefaults.standard.integer(forKey: "retentionDays")
        } else {
            self.retentionDays = 30 // Default to 30 days if not set
        }

        // Load selected model
        if let data = UserDefaults.standard.data(forKey: "selectedModel"),
           let model = try? JSONDecoder().decode(AIModel.self, from: data) {
            if model == .gpt51Mini {
                self.selectedModel = .gpt51Nano
            } else {
                self.selectedModel = model
            }
        } else {
            self.selectedModel = .gpt51Nano
        }

        let storedLanguage = UserDefaults.standard.string(forKey: "selectedLanguage")
        var resolvedLanguage = storedLanguage.flatMap { VoiceLanguage(rawValue: $0) } ?? VoiceLanguage.defaultLanguage

        // Load selected voice (default to Cartesia Sonic 3)
        let storedVoice: TTSVoice?
        if let data = UserDefaults.standard.data(forKey: "selectedVoice"),
           let voice = try? JSONDecoder().decode(TTSVoice.self, from: data) {
            storedVoice = voice
        } else {
            storedVoice = nil
        }
        let resolvedVoice = storedVoice ?? TTSVoice.default

        if resolvedVoice.language != resolvedLanguage {
            resolvedLanguage = resolvedVoice.language
        }

        self.selectedLanguage = resolvedLanguage
        self.selectedVoice = resolvedVoice

        // Load tool calling settings (default to enabled)
        // Load both values first, then set them in any order since didSet dependency logic
        // is skipped during initialization (via isInitializing flag)
        if UserDefaults.standard.object(forKey: "toolCallingEnabled") != nil {
            self.toolCallingEnabled = UserDefaults.standard.bool(forKey: "toolCallingEnabled")
        } else {
            self.toolCallingEnabled = true // Default to enabled
        }

        if UserDefaults.standard.object(forKey: "webSearchEnabled") != nil {
            self.webSearchEnabled = UserDefaults.standard.bool(forKey: "webSearchEnabled")
        } else {
            self.webSearchEnabled = true // Default to enabled
        }
        
        // Mark initialization as complete - dependency logic will now apply to future changes
        isInitializing = false
    }
}
