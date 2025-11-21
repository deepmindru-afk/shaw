//
//  VoiceModels.swift
//  Roadtrip
//

import Foundation

enum TTSProvider: String, Codable, CaseIterable {
    case cartesia
    case elevenlabs

    var displayName: String {
        switch self {
        case .cartesia: return "Cartesia"
        case .elevenlabs: return "ElevenLabs"
        }
    }
}

enum VoiceLanguage: String, Codable, CaseIterable, Identifiable {
    case english = "en-US"
    case spanish = "es-MX"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Spanish"
        }
    }

    var localeCode: String { rawValue }

    static var defaultLanguage: VoiceLanguage { .english }
}

struct TTSVoice: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String
    let provider: TTSProvider
    let requiresPro: Bool
    let language: VoiceLanguage
    let previewIdentifier: String

    private enum CodingKeys: String, CodingKey {
        case id, name, description, provider, requiresPro, language, previewIdentifier
    }

    init(
        id: String,
        name: String,
        description: String,
        provider: TTSProvider,
        requiresPro: Bool,
        language: VoiceLanguage,
        previewIdentifier: String
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.provider = provider
        self.requiresPro = requiresPro
        self.language = language
        self.previewIdentifier = previewIdentifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        provider = try container.decode(TTSProvider.self, forKey: .provider)
        requiresPro = try container.decode(Bool.self, forKey: .requiresPro)
        if let decodedLanguage = try container.decodeIfPresent(VoiceLanguage.self, forKey: .language) {
            language = decodedLanguage
        } else {
            language = TTSVoice.language(for: id) ?? .english
        }
        if let preview = try container.decodeIfPresent(String.self, forKey: .previewIdentifier) {
            previewIdentifier = preview
        } else {
            previewIdentifier = TTSVoice.legacyPreviewIdentifier(for: id, provider: provider)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        try container.encode(provider, forKey: .provider)
        try container.encode(requiresPro, forKey: .requiresPro)
        try container.encode(language, forKey: .language)
        try container.encode(previewIdentifier, forKey: .previewIdentifier)
    }

    private static func legacyPreviewIdentifier(for voiceID: String, provider: TTSProvider) -> String {
        let legacyMap: [String: String] = [
            "cartesia/sonic-3:9626c31c-bec5-4cca-baa8-f8ba9e84c8bc": "cartesia-jacqueline",
            "cartesia/sonic-3:a167e0f3-df7e-4d52-a9c3-f949145efdab": "cartesia-blake",
            "cartesia/sonic-3:f31cc6a7-c1e8-4764-980c-60a361443dd1": "cartesia-robyn",
            "cartesia/sonic-3:5c5ad5e7-1020-476b-8b91-fdcbe9cc313c": "cartesia-daniela",
            "elevenlabs/eleven_turbo_v2_5:cgSgspJ2msm6clMCkdW9": "elevenlabs-jessica",
            "elevenlabs/eleven_turbo_v2_5:iP95p4xoKVk53GoZ742B": "elevenlabs-chris",
            "elevenlabs/eleven_turbo_v2_5:Xb7hH8MSUJpSbSDYk0k2": "elevenlabs-alice",
            "elevenlabs/eleven_turbo_v2_5:cjVigY5qzO86Huf0OWal": "elevenlabs-eric"
        ]

        if let mapped = legacyMap[voiceID] {
            return mapped
        }

        return voiceID
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    private static let cartesiaVoices: [TTSVoice] = [
        // English
        TTSVoice(id: "cartesia/sonic-3:9626c31c-bec5-4cca-baa8-f8ba9e84c8bc", name: "Jacqueline", description: "Confident young American woman", provider: .cartesia, requiresPro: false, language: .english, previewIdentifier: "cartesia-jacqueline"),
        TTSVoice(id: "cartesia/sonic-3:a167e0f3-df7e-4d52-a9c3-f949145efdab", name: "Blake", description: "Energetic American man", provider: .cartesia, requiresPro: false, language: .english, previewIdentifier: "cartesia-blake"),
        TTSVoice(id: "cartesia/sonic-3:f31cc6a7-c1e8-4764-980c-60a361443dd1", name: "Robyn", description: "Calm Australian storyteller", provider: .cartesia, requiresPro: false, language: .english, previewIdentifier: "cartesia-robyn"),
        TTSVoice(id: "cartesia/sonic-3:f786b574-daa5-4673-aa0c-cbe3e8534c02", name: "Katie", description: "Professional English narrator", provider: .cartesia, requiresPro: false, language: .english, previewIdentifier: "cartesia-katie"),
        TTSVoice(id: "cartesia/sonic-3:228fca29-3a0a-435c-8728-5cb483251068", name: "Kiefer", description: "Polished baritone announcer", provider: .cartesia, requiresPro: false, language: .english, previewIdentifier: "cartesia-kiefer"),

        // Spanish
        TTSVoice(id: "cartesia/sonic-3:5c5ad5e7-1020-476b-8b91-fdcbe9cc313c", name: "Daniela", description: "Cálida locutora mexicana", provider: .cartesia, requiresPro: false, language: .spanish, previewIdentifier: "cartesia-daniela"),
        TTSVoice(id: "cartesia/sonic-3:6ccbfb76-1fc6-48f7-b71d-91ac6298247b", name: "Marisol", description: "Presentadora latina expresiva", provider: .cartesia, requiresPro: false, language: .spanish, previewIdentifier: "cartesia-marisol"),
        TTSVoice(id: "cartesia/sonic-3:c961b81c-a935-4c17-bfb3-ba2239de8c2f", name: "Santiago", description: "Narrador mexicano confiable", provider: .cartesia, requiresPro: false, language: .spanish, previewIdentifier: "cartesia-santiago")
    ]

    private static let elevenlabsVoices: [TTSVoice] = [
        // English
        TTSVoice(id: "elevenlabs/eleven_turbo_v2_5:cgSgspJ2msm6clMCkdW9", name: "Jessica", description: "Playful assistant with a smile", provider: .elevenlabs, requiresPro: false, language: .english, previewIdentifier: "elevenlabs-jessica"),
        TTSVoice(id: "elevenlabs/eleven_turbo_v2_5:iP95p4xoKVk53GoZ742B", name: "Chris", description: "Natural American narrator", provider: .elevenlabs, requiresPro: false, language: .english, previewIdentifier: "elevenlabs-chris"),
        TTSVoice(id: "elevenlabs/eleven_turbo_v2_5:Xb7hH8MSUJpSbSDYk0k2", name: "Alice", description: "Friendly British guide", provider: .elevenlabs, requiresPro: false, language: .english, previewIdentifier: "elevenlabs-alice"),
        TTSVoice(id: "elevenlabs/eleven_turbo_v2_5:21m00Tcm4TlvDq8ikWAM", name: "Rachel", description: "Balanced studio narrator", provider: .elevenlabs, requiresPro: false, language: .english, previewIdentifier: "elevenlabs-rachel"),
        TTSVoice(id: "elevenlabs/eleven_turbo_v2_5:CwhRBWXzGAHq8TQ4Fs17", name: "Roger", description: "Easygoing conversational tone", provider: .elevenlabs, requiresPro: false, language: .english, previewIdentifier: "elevenlabs-roger"),
        TTSVoice(id: "elevenlabs/eleven_turbo_v2_5:2EiwWnXFnvU5JabPnv8n", name: "Clyde", description: "Warm, confident storyteller", provider: .elevenlabs, requiresPro: false, language: .english, previewIdentifier: "elevenlabs-clyde"),
        TTSVoice(id: "elevenlabs/eleven_turbo_v2_5:EXAVITQu4vr4xnSDxMaL", name: "Sarah", description: "Bright, upbeat assistant", provider: .elevenlabs, requiresPro: false, language: .english, previewIdentifier: "elevenlabs-sarah"),

        // Spanish
        TTSVoice(id: "elevenlabs/eleven_turbo_v2_5:cjVigY5qzO86Huf0OWal", name: "Eric", description: "Hablante mexicano con voz suave", provider: .elevenlabs, requiresPro: false, language: .spanish, previewIdentifier: "elevenlabs-eric"),
        TTSVoice(id: "elevenlabs/eleven_turbo_v2_5:FGY2WhTYpPnrIDTdsKH5", name: "Lucía", description: "Guía latina optimista", provider: .elevenlabs, requiresPro: false, language: .spanish, previewIdentifier: "elevenlabs-lucia"),
        TTSVoice(id: "elevenlabs/eleven_turbo_v2_5:IKne3meq5aSn9XLyUdCD", name: "Diego", description: "Acompañante latino relajado", provider: .elevenlabs, requiresPro: false, language: .spanish, previewIdentifier: "elevenlabs-diego"),
        TTSVoice(id: "elevenlabs/eleven_turbo_v2_5:AZnzlk1XvdvUeBnXmlld", name: "Paloma", description: "Conductora clara y cercana", provider: .elevenlabs, requiresPro: false, language: .spanish, previewIdentifier: "elevenlabs-paloma"),
        TTSVoice(id: "elevenlabs/eleven_turbo_v2_5:TxGEqnHWrfWFTfGW9XjX", name: "Andrés", description: "Locutor masculino seguro", provider: .elevenlabs, requiresPro: false, language: .spanish, previewIdentifier: "elevenlabs-andres"),
        TTSVoice(id: "elevenlabs/eleven_turbo_v2_5:VR6AewLTigWG4xSOukaG", name: "Sergio", description: "Voz firme y confiable", provider: .elevenlabs, requiresPro: false, language: .spanish, previewIdentifier: "elevenlabs-sergio"),
        TTSVoice(id: "elevenlabs/eleven_turbo_v2_5:pNInz6obpgDQGcFmaJgB", name: "Valeria", description: "Asesora latina cercana", provider: .elevenlabs, requiresPro: false, language: .spanish, previewIdentifier: "elevenlabs-valeria"),
        TTSVoice(id: "elevenlabs/eleven_turbo_v2_5:ErXwobaYiN019PkySvjV", name: "Camila", description: "Asistente dinámica en español", provider: .elevenlabs, requiresPro: false, language: .spanish, previewIdentifier: "elevenlabs-camila"),
        TTSVoice(id: "elevenlabs/eleven_turbo_v2_5:ZQe5CZNOzWyzPSCn5a3c", name: "Javier", description: "Experto latino confiable", provider: .elevenlabs, requiresPro: false, language: .spanish, previewIdentifier: "elevenlabs-javier")
    ]

    static func voices(for provider: TTSProvider, language: VoiceLanguage? = nil) -> [TTSVoice] {
        switch provider {
        case .cartesia: return filter(voices: cartesiaVoices, language: language)
        case .elevenlabs: return filter(voices: elevenlabsVoices, language: language)
        }
    }

    static func voices(for language: VoiceLanguage) -> [TTSVoice] {
        return allVoices.filter { $0.language == language }
    }

    static func availableLanguages() -> [VoiceLanguage] {
        return VoiceLanguage.allCases.filter { !voices(for: $0).isEmpty }
    }

    static var allVoices: [TTSVoice] {
        cartesiaVoices + elevenlabsVoices
    }

    static func language(for voiceID: String) -> VoiceLanguage? {
        return allVoices.first(where: { $0.id == voiceID })?.language
    }

    private static func filter(voices: [TTSVoice], language: VoiceLanguage?) -> [TTSVoice] {
        guard let language else { return voices }
        return voices.filter { $0.language == language }
    }

    static let `default` = cartesiaVoices.first(where: { $0.language == .english }) ?? cartesiaVoices[0]
}

enum AIModelProvider: String, Codable, CaseIterable {
    case openai
    case anthropic
    case google
    case xai

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .google: return "Google"
        case .xai: return "xAI"
        }
    }
}

enum AIModel: String, Codable, CaseIterable {
    // OpenAI GPT-4o Series
    case gpt4o = "openai/gpt-4o"
    case gpt4oMini = "openai/gpt-4o-mini"

    // Anthropic Claude 4.5 Series
    case claudeSonnet45 = "claude-sonnet-4-5"
    case claudeHaiku45 = "claude-haiku-4-5"

    // Google Gemini 2.5 Series
    case gemini25Pro = "google/gemini-2.5-pro"
    case gemini25Flash = "google/gemini-2.5-flash"
    case gemini25FlashLite = "google/gemini-2.5-flash-lite"

    // xAI Grok Series
    case grok4 = "xai/grok-4"
    case grok4Mini = "xai/grok-4-mini"

    private static let legacyModelMap: [String: AIModel] = [
        "openai/gpt-5.1": .gpt4o,
        "openai/gpt-5.1-mini": .gpt4oMini,
        "openai/gpt-5.1-nano": .gpt4oMini,
        "openai/gpt-5": .gpt4o,
        "openai/gpt-5-mini": .gpt4oMini,
        "openai/gpt-5-nano": .gpt4oMini,
        "openai/gpt-4.1": .gpt4o,
        "openai/gpt-4.1-mini": .gpt4oMini,
        "openai/gpt-4.1-nano": .gpt4oMini,
        "openai/gpt-4o-realtime-preview": .gpt4o,
        "openai/gpt-oss-120b": .gpt4o
    ]

    static var allCases: [AIModel] {
        [
            .gpt4o,
            .gpt4oMini,
            .claudeSonnet45,
            .claudeHaiku45,
            .gemini25Pro,
            .gemini25Flash,
            .gemini25FlashLite,
            .grok4,
            .grok4Mini
        ]
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        if let model = AIModel(rawValue: value) {
            self = model
            return
        }

        switch value {
        case let legacy where AIModel.legacyModelMap.keys.contains(legacy):
            self = AIModel.legacyModelMap[legacy] ?? .gpt4oMini
        case "google/gemini-2.0-flash":
            self = .gemini25Flash
        case "google/gemini-2.0-flash-lite":
            self = .gemini25FlashLite
        case "xai/grok-2":
            self = .grok4
        case "xai/grok-2-mini":
            self = .grok4Mini
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown AI model: \(value)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var provider: AIModelProvider {
        switch self {
        case .gpt4o, .gpt4oMini:
            return .openai
        case .claudeSonnet45, .claudeHaiku45:
            return .anthropic
        case .gemini25Pro, .gemini25Flash, .gemini25FlashLite:
            return .google
        case .grok4, .grok4Mini:
            return .xai
        }
    }

    var displayName: String {
        switch self {
        case .gpt4o: return "GPT-4o"
        case .gpt4oMini: return "GPT-4o Mini"
        case .claudeSonnet45: return "Claude Sonnet 4.5"
        case .claudeHaiku45: return "Claude Haiku 4.5"
        case .gemini25Pro: return "Gemini 2.5 Pro"
        case .gemini25Flash: return "Gemini 2.5 Flash"
        case .gemini25FlashLite: return "Gemini 2.5 Flash Lite"
        case .grok4: return "Grok 4"
        case .grok4Mini: return "Grok 4 Mini"
        }
    }

    var description: String {
        switch self {
        case .gpt4o: return "GPT-4o - Flagship multimodal reasoning"
        case .gpt4oMini: return "GPT-4o Mini - Fast and capable"
        case .claudeSonnet45: return "Most capable Claude - Best for complex tasks"
        case .claudeHaiku45: return "Fast Claude - Great for quick responses"
        case .gemini25Pro: return "Most capable Gemini - Best for reasoning"
        case .gemini25Flash: return "Fast multimodal Gemini"
        case .gemini25FlashLite: return "Ultra-fast Gemini"
        case .grok4: return "Grok 4 - Cutting-edge xAI model"
        case .grok4Mini: return "Grok 4 Mini - Faster Grok variant"
        }
    }

    var requiresPro: Bool {
        switch self {
        case .gpt4o, .claudeSonnet45, .gemini25Pro, .grok4:
            return true
        default:
            return false
        }
    }

    static func models(for provider: AIModelProvider) -> [AIModel] {
        return allCases.filter { $0.provider == provider }
    }
}
