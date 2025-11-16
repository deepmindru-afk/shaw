//
//  CallScreen.swift
//  Shaw
//

import SwiftUI

struct CallScreen: View {
    @ObservedObject private var callCoordinator = AssistantCallCoordinator.shared
    @ObservedObject private var appCoordinator = AppCoordinator.shared
    @ObservedObject private var settings = UserSettings.shared
    @State private var showErrorAlert = false
    @State private var selectedLoggingOption: LoggingOption?
    
    enum LoggingOption {
        case enabled
        case disabled
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if callCoordinator.callState == .idle {
                    Form {
                        Section {
                            NavigationLink(destination: VoicePickerView(settings: settings)) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(settings.selectedVoice.provider.displayName)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        Text(settings.selectedVoice.name)
                                            .font(.body)
                                    }
                                    Spacer()
                                }
                            }
                            .accessibilityLabel("Voice: \(settings.selectedVoice.name)")
                            .accessibilityHint("Double tap to change voice")
                        } header: {
                            Text("Voice")
                        } footer: {
                            if settings.selectedVoice.isRealtimeMode {
                                Text("Ultra-low latency voice conversation with natural, real-time responses")
                            } else {
                                Text("High-quality voice synthesis optimized for cost efficiency")
                            }
                        }

                        if !settings.selectedVoice.isRealtimeMode {
                            Section {
                                NavigationLink(destination: ModelPickerView(settings: settings)) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(settings.selectedModel.provider.displayName)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                            Text(settings.selectedModel.displayName)
                                                .font(.body)
                                        }
                                        Spacer()
                                    }
                                }
                                .accessibilityLabel("AI Model: \(settings.selectedModel.displayName)")
                                .accessibilityHint("Double tap to change AI model")
                            } header: {
                                Text("AI Model")
                            } footer: {
                                Text("Choose how smart and fast your assistant responds to your questions")
                            }
                        }

                        Section {
                            LoggingOptionsView(
                                selectedOption: $selectedLoggingOption,
                                settings: settings
                            )
                        } header: {
                            Text("Recording")
                        }
                    }
                } else if callCoordinator.callState == .connected {
                    VStack(spacing: 24) {
                        Spacer()

                        MicrophoneActivityView()
                            .padding(.horizontal, 24)

                        StatusIndicatorView(
                            isLoggingEnabled: selectedLoggingOption == .enabled
                        )
                        .padding(.horizontal, 24)

                        Spacer()
                    }
                } else {
                    Spacer()
                }

                Spacer()
                    .frame(height: 120)
            }

            VStack(spacing: 8) {
                if let errorMessage = callCoordinator.errorMessage {
                    ErrorIndicatorView(message: errorMessage)
                        .padding(.horizontal, 24)
                }

                callButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
        }
        .navigationTitle("Call")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if selectedLoggingOption == nil {
                selectedLoggingOption = settings.loggingEnabled ? .enabled : .disabled
            }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {
                callCoordinator.errorMessage = nil
            }
        } message: {
            if let errorMessage = callCoordinator.errorMessage {
                Text(errorMessage)
            }
        }
        .onChange(of: callCoordinator.errorMessage) { oldValue, newValue in
            showErrorAlert = newValue != nil
        }
    }

    private var callButton: some View {
        CallButtonView(
            selectedLoggingOption: selectedLoggingOption ?? .enabled
        )
    }
    
}

struct LoggingOptionsView: View {
    @Binding var selectedOption: CallScreen.LoggingOption?
    @ObservedObject var settings: UserSettings

    var body: some View {
        VStack(spacing: 12) {
            Button(action: {
                HapticFeedbackService.shared.selection()
                selectedOption = .enabled
                settings.loggingEnabled = true
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Save & Summarize")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Record conversation history and get AI-generated summaries")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if selectedOption == .enabled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                    } else {
                        Image(systemName: "circle")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Button(action: {
                HapticFeedbackService.shared.selection()
                selectedOption = .disabled
                settings.loggingEnabled = false
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Voice Only")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("No recording or history will be saved")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if selectedOption == .disabled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                    } else {
                        Image(systemName: "circle")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

struct CallButtonView: View {
    @ObservedObject private var callCoordinator = AssistantCallCoordinator.shared
    let selectedLoggingOption: CallScreen.LoggingOption

    var body: some View {
        Button(action: {
            if callCoordinator.callState == .idle {
                HapticFeedbackService.shared.medium()
                let enableLogging = selectedLoggingOption == .enabled
                callCoordinator.startAssistantCall(context: "phone", enableLogging: enableLogging)
            } else {
                HapticFeedbackService.shared.medium()
                callCoordinator.endAssistantCall()
            }
        }) {
            HStack(spacing: 12) {
                if callCoordinator.callState == .connecting || callCoordinator.callState == .disconnecting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: callCoordinator.callState == .idle ? "phone.fill" : "phone.down.fill")
                        .font(.system(size: 24, weight: .semibold))
                }
                
                Text(buttonText)
                    .font(.system(size: 20, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(buttonGradient)
            .cornerRadius(32)
            .shadow(color: buttonShadowColor.opacity(0.4), radius: 12, x: 0, y: 6)
        }
        .disabled(callCoordinator.callState == .connecting || callCoordinator.callState == .disconnecting)
        .animation(.easeInOut(duration: 0.3), value: callCoordinator.callState)
        .accessibilityLabel(buttonText)
        .accessibilityHint(callCoordinator.callState == .idle ? "Double tap to start a call" : "Double tap to end the call")
    }
    
    private var buttonText: String {
        switch callCoordinator.callState {
        case .idle:
            return "Start Call"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "End Call"
        case .disconnecting:
            return "Disconnecting..."
        }
    }
    
    private var buttonGradient: LinearGradient {
        switch callCoordinator.callState {
        case .idle:
            return LinearGradient(
                colors: [.blue, .blue.opacity(0.8)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .connecting, .disconnecting:
            return LinearGradient(
                colors: [.gray, .gray.opacity(0.8)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .connected:
            return LinearGradient(
                colors: [.red, .red.opacity(0.8)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
    
    private var buttonShadowColor: Color {
        switch callCoordinator.callState {
        case .idle:
            return .blue
        case .connecting, .disconnecting:
            return .gray
        case .connected:
            return .red
        }
    }
}

struct MicrophoneActivityView: View {
    @ObservedObject private var monitor = MicrophoneLevelMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(monitor.isMonitoring ? "Microphone is live" : "Starting microphone…")
                        .font(.headline)
                    Text("Speak naturally—your assistant is listening.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            MicrophoneWaveformView(level: monitor.level)
                .frame(height: 48)
        }
        .padding(.vertical, 6)
        .onAppear { monitor.startMonitoring() }
        .onDisappear { monitor.stopMonitoring() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(monitor.isMonitoring ? "Microphone is live" : "Starting microphone")
        .accessibilityValue("Input level \(Int(monitor.level * 100)) percent")
    }
}

struct MicrophoneWaveformView: View {
    var level: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 45.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                context.blendMode = .plusLighter
                context.addFilter(.shadow(color: Color.accentColor.opacity(0.2), radius: 6, x: 0, y: 4))
                drawWaves(in: &context, size: size, time: time)
            }
        }
    }

    private func drawWaves(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let normalized = max(0, min(1, level))
        let baseAmplitude = normalized * (size.height / 2.0)

        let waves: [Wave] = [
            Wave(multiplier: 1.0, frequency: 1.8, speed: 1.3, lineWidth: 4, phaseOffset: 0, color: Color.accentColor),
            Wave(multiplier: 0.65, frequency: 2.8, speed: 1.6, lineWidth: 3, phaseOffset: .pi / 2, color: Color.accentColor.opacity(0.8)),
            Wave(multiplier: 0.35, frequency: 4.0, speed: 2.0, lineWidth: 2, phaseOffset: .pi, color: Color.accentColor.opacity(0.5))
        ]

        for wave in waves {
            let amplitude = baseAmplitude * wave.multiplier
            let phase = CGFloat(time) * wave.speed + wave.phaseOffset
            let path = wavePath(size: size, amplitude: amplitude, phase: phase, frequency: wave.frequency)

            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [wave.color, wave.color.opacity(0.4)]),
                    startPoint: CGPoint(x: 0, y: size.height / 2),
                    endPoint: CGPoint(x: size.width, y: size.height / 2)
                ),
                style: StrokeStyle(lineWidth: wave.lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func wavePath(size: CGSize, amplitude: CGFloat, phase: CGFloat, frequency: CGFloat) -> Path {
        var path = Path()
        let width = size.width
        let midY = size.height / 2
        let step = max(1, width / 120)

        path.move(to: CGPoint(x: 0, y: midY))

        var x: CGFloat = 0
        while x <= width {
            let progress = x / width
            let angle = progress * frequency * .pi * 2 + phase
            let y = midY + sin(angle) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
            x += step
        }

        return path
    }

    private struct Wave {
        let multiplier: CGFloat
        let frequency: CGFloat
        let speed: CGFloat
        let lineWidth: CGFloat
        let phaseOffset: CGFloat
        let color: Color
    }
}

struct StatusIndicatorView: View {
    let isLoggingEnabled: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.green)
                .frame(width: 10, height: 10)
            
            Text(isLoggingEnabled ? "Recording and summarizing this call" : "Voice-only mode: No recording")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(20)
    }
}

struct ErrorIndicatorView: View {
    let message: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.caption)
            
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(20)
    }
}

struct ModelPickerView: View {
    @ObservedObject var settings: UserSettings
    @StateObject private var subscriptionManager = SubscriptionManager.shared

    var body: some View {
        List {
            ForEach(AIModelProvider.allCases, id: \.self) { provider in
                let models = AIModel.models(for: provider)
                Section {
                    ForEach(models, id: \.self) { model in
                        Button {
                            if model.requiresPro && !subscriptionManager.state.isActive {
                                // Don't allow selection of Pro models for non-Pro users
                                HapticFeedbackService.shared.warning()
                                return
                            }
                            HapticFeedbackService.shared.selection()
                            settings.selectedModel = model
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(model.displayName)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        if model.requiresPro && !subscriptionManager.state.isActive {
                                            Text("PRO")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.blue)
                                                .cornerRadius(3)
                                        }
                                    }
                                    Text(model.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if settings.selectedModel == model {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                        .fontWeight(.bold)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .contentShape(Rectangle())
                            .animation(.easeInOut(duration: 0.2), value: settings.selectedModel == model)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.requiresPro && !subscriptionManager.state.isActive)
                        .opacity(model.requiresPro && !subscriptionManager.state.isActive ? 0.5 : 1.0)
                    }
                } header: {
                    HStack {
                        Text(provider.displayName)
                        if models.contains(where: { $0.requiresPro }) {
                            Text("PRO")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .cornerRadius(4)
                        }
                    }
                }
            }
        }
        .navigationTitle("AI Model")
        .navigationBarTitleDisplayMode(.large)
    }
}

struct VoicePickerView: View {
    @ObservedObject var settings: UserSettings
    @StateObject private var subscriptionManager = SubscriptionManager.shared

    var body: some View {
        List {
            ForEach(TTSProvider.allCases, id: \.self) { provider in
                let voices = TTSVoice.voices(for: provider)
                Section {
                    ForEach(voices) { voice in
                        Button {
                            if voice.requiresPro && !subscriptionManager.state.isActive {
                                // Don't allow selection of Pro voices for non-Pro users
                                HapticFeedbackService.shared.warning()
                                return
                            }
                            HapticFeedbackService.shared.selection()
                            settings.selectedVoice = voice
                        } label: {
                            VoicePickerRow(
                                voice: voice,
                                isSelected: settings.selectedVoice.id == voice.id,
                                isPro: subscriptionManager.state.isActive
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(voice.requiresPro && !subscriptionManager.state.isActive)
                        .opacity(voice.requiresPro && !subscriptionManager.state.isActive ? 0.5 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: settings.selectedVoice.id)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(provider.displayName)
                            if voices.first?.requiresPro == true {
                                Text("PRO")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue)
                                    .cornerRadius(4)
                            }
                        }
                        if provider == .cartesia {
                            Text("High-quality, natural voices")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textCase(.none)
                        } else if provider == .elevenlabs {
                            Text("Premium, ultra-realistic voices")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textCase(.none)
                        } else if provider == .openaiRealtime {
                            Text("Highest quality real-time interactions")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textCase(.none)
                        }
                    }
                }
            }
        }
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.large)
    }
}

struct VoicePickerRow: View {
    let voice: TTSVoice
    let isSelected: Bool
    let isPro: Bool
    @StateObject private var previewService = VoicePreviewService.shared
    @State private var isLoadingPreview = false
    @State private var previewError: String?

    private var isPlaying: Bool {
        previewService.isPlaying(for: voice)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(voice.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    if voice.requiresPro && !isPro {
                        Text("PRO")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue)
                            .cornerRadius(3)
                    }
                }
                Text(voice.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isLoadingPreview {
                ProgressView()
            } else {
                Button(action: {
                    Task {
                        await togglePreview()
                    }
                }) {
                    Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .foregroundColor(isPlaying ? .red : .blue)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(.blue)
                    .fontWeight(.bold)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .onChange(of: previewService.playingVoiceId) {
            // Update UI when playback state changes
        }
    }

    private func togglePreview() async {
        if isPlaying {
            previewService.stopPreview(for: voice)
        } else {
            previewService.stopAllPreviews()
            isLoadingPreview = true
            previewError = nil

            do {
                try await previewService.playPreview(for: voice)
            } catch {
                previewError = error.localizedDescription
                print("Failed to play preview: \(error)")
            }

            isLoadingPreview = false
        }
    }
}

#Preview {
    CallScreen()
}
