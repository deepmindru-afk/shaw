//
//  VoiceModels.swift
//  Shaw
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

struct TTSVoice: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String
    let provider: TTSProvider
    
    static let cartesiaVoices: [TTSVoice] = [
        TTSVoice(id: "cartesia-katie", name: "Katie", description: "Friendly female voice", provider: .cartesia),
        TTSVoice(id: "cartesia-kiefer", name: "Kiefer", description: "Professional male voice", provider: .cartesia),
        TTSVoice(id: "cartesia-kyle", name: "Kyle", description: "Casual male voice", provider: .cartesia),
        TTSVoice(id: "cartesia-tessa", name: "Tessa", description: "Warm female voice", provider: .cartesia)
    ]
    
    static let elevenlabsVoices: [TTSVoice] = [
        TTSVoice(id: "elevenlabs-rachel", name: "Rachel", description: "Clear female voice", provider: .elevenlabs),
        TTSVoice(id: "elevenlabs-clyde", name: "Clyde", description: "Deep male voice", provider: .elevenlabs),
        TTSVoice(id: "elevenlabs-roger", name: "Roger", description: "Mature male voice", provider: .elevenlabs),
        TTSVoice(id: "elevenlabs-sarah", name: "Sarah", description: "Young female voice", provider: .elevenlabs),
        TTSVoice(id: "elevenlabs-laura", name: "Laura", description: "Professional female voice", provider: .elevenlabs),
        TTSVoice(id: "elevenlabs-charlie", name: "Charlie", description: "Energetic male voice", provider: .elevenlabs)
    ]
    
    static func voices(for provider: TTSProvider) -> [TTSVoice] {
        switch provider {
        case .cartesia: return cartesiaVoices
        case .elevenlabs: return elevenlabsVoices
        }
    }
    
    static let `default` = cartesiaVoices[0]
}

enum AIModel: String, Codable, CaseIterable {
    // GPT-4.1 Series (Newest)
    case gpt41 = "openai/gpt-4.1"
    case gpt41Mini = "openai/gpt-4.1-mini"
    case gpt41Nano = "openai/gpt-4.1-nano"

    // GPT-5 Series
    case gpt5 = "openai/gpt-5"
    case gpt5Mini = "openai/gpt-5-mini"
    case gpt5Nano = "openai/gpt-5-nano"

    // GPT-4o Series
    case gpt4o = "openai/gpt-4o"
    case gpt4oMini = "openai/gpt-4o-mini"

    // Open Source
    case gptOss120B = "openai/gpt-oss-120b"

    var displayName: String {
        switch self {
        case .gpt41: return "GPT-4.1"
        case .gpt41Mini: return "GPT-4.1 Mini"
        case .gpt41Nano: return "GPT-4.1 Nano"
        case .gpt5: return "GPT-5"
        case .gpt5Mini: return "GPT-5 Mini"
        case .gpt5Nano: return "GPT-5 Nano"
        case .gpt4o: return "GPT-4o"
        case .gpt4oMini: return "GPT-4o Mini"
        case .gptOss120B: return "GPT OSS 120B"
        }
    }

    var description: String {
        switch self {
        case .gpt41: return "Latest GPT-4.1 - Most capable reasoning"
        case .gpt41Mini: return "Balanced speed and capability"
        case .gpt41Nano: return "Ultra-fast, efficient for simple tasks"
        case .gpt5: return "GPT-5 - Next generation model"
        case .gpt5Mini: return "GPT-5 Mini - Fast and capable"
        case .gpt5Nano: return "GPT-5 Nano - Lightning fast"
        case .gpt4o: return "GPT-4o - Powerful multimodal model"
        case .gpt4oMini: return "GPT-4o Mini - Fast and efficient"
        case .gptOss120B: return "Open source 120B parameter model"
        }
    }
}
