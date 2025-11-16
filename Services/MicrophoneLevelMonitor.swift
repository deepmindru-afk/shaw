//
//  MicrophoneLevelMonitor.swift
//  Shaw
//

import Foundation
import AVFoundation
import SwiftUI

@MainActor
final class MicrophoneLevelMonitor: ObservableObject {
    static let shared = MicrophoneLevelMonitor()

    @Published private(set) var level: CGFloat = 0
    @Published private(set) var isMonitoring = false

    private var audioRecorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var fallbackTimer: Timer?
    private let smoothingFactor: CGFloat = 0.25

    private init() {}

    func startMonitoring() {
        guard !isMonitoring else { return }
        handlePermission()
    }

    func stopMonitoring() {
        audioRecorder?.stop()
        audioRecorder = nil

        levelTimer?.invalidate()
        levelTimer = nil

        fallbackTimer?.invalidate()
        fallbackTimer = nil

        level = 0
        isMonitoring = false
    }

    private func handlePermission() {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .granted:
            startRecorder(with: session)
        case .denied:
            startFallbackAnimation()
        case .undetermined:
            session.requestRecordPermission { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    granted ? self.startRecorder(with: session) : self.startFallbackAnimation()
                }
            }
        @unknown default:
            startFallbackAnimation()
        }
    }

    private func startRecorder(with session: AVAudioSession) {
        do {
            let url = URL(fileURLWithPath: "/dev/null")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatAppleLossless,
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()
            recorder.record()

            audioRecorder = recorder
            startLevelUpdates()
        } catch {
            print("Failed to start microphone monitor: \(error)")
            startFallbackAnimation()
        }
    }

    private func startLevelUpdates() {
        isMonitoring = true

        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.audioRecorder?.updateMeters()
            if let power = self.audioRecorder?.averagePower(forChannel: 0) {
                let normalized = self.normalizedPower(from: power)
                let smoothed = normalized * self.smoothingFactor + self.level * (1 - self.smoothingFactor)
                self.level = smoothed < 0.03 ? 0 : smoothed
            } else {
                self.level = 0
            }
        }
    }

    private func normalizedPower(from decibels: Float) -> CGFloat {
        let minDb: Float = -80
        guard decibels > minDb else { return 0 }
        let scaled = (decibels + abs(minDb)) / abs(minDb)
        return CGFloat(max(0, min(1, scaled)))
    }

    private func startFallbackAnimation() {
        isMonitoring = true
        fallbackTimer?.invalidate()
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let base = CGFloat.random(in: 0.1...0.25)
            let variance = CGFloat.random(in: 0...0.15)
            self.level = min(1, base + variance)
        }
    }
}
