//
//  VoicePreviewService.swift
//  AI Voice Copilot
//

import Foundation
import AVFoundation
import Combine

/// Service for generating and caching voice preview audio samples
@MainActor
class VoicePreviewService: NSObject, ObservableObject {
    static let shared = VoicePreviewService()
    
    private var audioPlayers: [String: AVAudioPlayer] = [:]
    private var previewCache: [String: URL] = [:]
    @Published var playingVoiceId: String?
    
    private override init() {
        super.init()
    }
    
    /// Generate or retrieve cached preview URL for a voice
    func getPreviewURL(for voice: TTSVoice) async throws -> URL {
        let cacheKey = voice.id
        
        // Check if already cached
        if let cachedURL = previewCache[cacheKey] {
            return cachedURL
        }
        
        // Generate preview via backend
        let url = try await generatePreview(voice: voice)
        previewCache[cacheKey] = url
        return url
    }
    
    /// Play preview for a voice
    func playPreview(for voice: TTSVoice) async throws {
        let cacheKey = voice.id
        
        // Stop any currently playing preview
        stopAllPreviews()
        
        // Get or generate preview URL
        let previewURL = try await getPreviewURL(for: voice)
        
        // Create and play audio player
        let player = try AVAudioPlayer(contentsOf: previewURL)
        player.delegate = self
        player.prepareToPlay()
        audioPlayers[cacheKey] = player
        playingVoiceId = cacheKey
        player.play()
    }
    
    /// Stop preview for a specific voice
    func stopPreview(for voice: TTSVoice) {
        let cacheKey = voice.id
        audioPlayers[cacheKey]?.stop()
        audioPlayers[cacheKey] = nil
        if playingVoiceId == cacheKey {
            playingVoiceId = nil
        }
    }
    
    /// Stop all playing previews
    func stopAllPreviews() {
        audioPlayers.values.forEach { $0.stop() }
        audioPlayers.removeAll()
        playingVoiceId = nil
    }
    
    /// Check if a preview is currently playing for a voice
    func isPlaying(for voice: TTSVoice) -> Bool {
        let cacheKey = voice.id
        return playingVoiceId == cacheKey && (audioPlayers[cacheKey]?.isPlaying ?? false)
    }
    
    /// Map voice ID to preview file name
    /// Maps the app's voice IDs to the backend preview file names
    private func getPreviewFileName(for voice: TTSVoice) -> String {
        return voice.previewIdentifier
    }
    
    /// Get preview audio URL (pre-generated static file)
    private func generatePreview(voice: TTSVoice) async throws -> URL {
        let configuration = Configuration.shared

        // Determine file extension based on provider
        let fileExtension: String
        let voiceFileName: String

        switch voice.provider {
        case .cartesia:
            fileExtension = "wav"
            voiceFileName = getPreviewFileName(for: voice)
        case .elevenlabs:
            fileExtension = "mp3"
            voiceFileName = getPreviewFileName(for: voice)
        }

        // Construct base URL pointing at the API host instead of /v1
        guard let apiURL = URL(string: configuration.apiBaseURL),
              var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false) else {
            throw VoicePreviewError.invalidURL
        }

        components.path = ""
        components.query = nil
        components.fragment = nil

        guard let previewBaseURL = components.url else {
            throw VoicePreviewError.invalidURL
        }

        // Use the static file endpoint: /voice-previews/{voiceId}.{ext}
        let previewURL = previewBaseURL
            .appendingPathComponent("voice-previews")
            .appendingPathComponent("\(voiceFileName).\(fileExtension)")

        // Check if file already exists in cache
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let cacheSubDir = cacheDir.appendingPathComponent("voice-previews", isDirectory: true)
        
        // Create cache directory if it doesn't exist
        try? FileManager.default.createDirectory(at: cacheSubDir, withIntermediateDirectories: true)
        
        let fileName = "\(voiceFileName)-preview.\(fileExtension)"
        let cachedFileURL = cacheSubDir.appendingPathComponent(fileName)
        
        // If file already exists locally, use it
        if FileManager.default.fileExists(atPath: cachedFileURL.path) {
            return cachedFileURL
        }
        
        // Download and cache the preview file
        let (data, response) = try await URLSession.shared.data(from: previewURL)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("❌ Failed to download preview: HTTP \(statusCode) from \(previewURL.absoluteString)")
            throw VoicePreviewError.generationFailed
        }

        // Save to cache directory for persistent storage
        try data.write(to: cachedFileURL)
        print("✅ Cached preview: \(fileName) (\(data.count) bytes)")
        return cachedFileURL
    }
}

extension VoicePreviewService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            // Find and remove the finished player
            if let voiceId = playingVoiceId, audioPlayers[voiceId] === player {
                audioPlayers[voiceId] = nil
                playingVoiceId = nil
            }
        }
    }
    
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            if let voiceId = playingVoiceId, audioPlayers[voiceId] === player {
                audioPlayers[voiceId] = nil
                playingVoiceId = nil
            }
        }
    }
}

enum VoicePreviewError: LocalizedError {
    case invalidURL
    case generationFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid preview URL"
        case .generationFailed:
            return "Failed to generate voice preview"
        }
    }
}
