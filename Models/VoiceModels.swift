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
    case gpt4oMini = "gpt-4o-mini"
    case gpt4o = "gpt-4o"
    case gpt4Turbo = "gpt-4-turbo"

    var displayName: String {
        switch self {
        case .gpt4oMini: return "GPT-4o Mini"
        case .gpt4o: return "GPT-4o"
        case .gpt4Turbo: return "GPT-4 Turbo"
        }
    }

    var description: String {
        switch self {
        case .gpt4oMini: return "Fast and efficient for most conversations"
        case .gpt4o: return "Best balance of speed and capability"
        case .gpt4Turbo: return "Most capable, longer context"
        }
    }
}
