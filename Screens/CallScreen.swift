//
//  CallScreen.swift
//  Roadtrip
//

import SwiftUI

struct CallScreen: View {
    @ObservedObject private var callCoordinator = AssistantCallCoordinator.shared
    @ObservedObject private var appCoordinator = AppCoordinator.shared
    @ObservedObject private var settings = UserSettings.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared
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
                            switch settings.selectedVoice.provider {
                            case .cartesia:
                                Text("High-quality neural voice optimized for smooth, natural responses")
                            case .elevenlabs:
                                Text("Premium ultra-realistic voice tuned for expressive conversations")
                            }
                        }

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

                        Section {
                            NavigationLink(destination: LanguagePickerView(settings: settings)) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Speaking language")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        Text(settings.selectedLanguage.displayName)
                                            .font(.body)
                                    }
                                    Spacer()
                                }
                            }
                            .accessibilityLabel("Language: \(settings.selectedLanguage.displayName)")
                            .accessibilityHint("Double tap to change language")
                        } header: {
                            Text("Language")
                        } footer: {
                            Text("Sets speech recognition and assistant defaults. Voice options are filtered on the next screen.")
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
            if !subscriptionManager.state.isActive && settings.selectedModel.requiresPro {
                settings.selectedModel = .gpt4oMini
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

struct ModelRowView: View {
    let title: String
    let description: String
    let showProBadge: Bool
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    if showProBadge {
                        ProBadge()
                    }
                }
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(.blue)
                    .fontWeight(.bold)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

struct ModelSelectionRow: View {
    let model: AIModel
    let isSelected: Bool
    let isPro: Bool
    let onSelect: () -> Void
    let onRequirePro: () -> Void

    var body: some View {
        Button {
            if model.requiresPro && !isPro {
                onRequirePro()
            } else {
                onSelect()
            }
        } label: {
            ModelRowView(
                title: model.displayName,
                description: model.description,
                showProBadge: model.requiresPro && !isPro,
                isSelected: isSelected
            )
        }
        .buttonStyle(.plain)
    }
}

struct LanguageRowView: View {
    let title: String
    let subtitle: String
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(.blue)
                    .fontWeight(.bold)
            }
        }
        .contentShape(Rectangle())
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 34))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(monitor.isMonitoring ? "Microphone is live" : "Starting microphone…")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Speak naturally—your assistant is listening.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(0.15),
                                Color.cyan.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.25))
                    )

                MicrophoneWaveformCanvas(level: monitor.level)
                    .padding(.horizontal, 6)
            }
            .frame(height: 70)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(Color.blue.opacity(0.1))
        )
        .shadow(color: Color.black.opacity(0.08), radius: 20, x: 0, y: 12)
        .onAppear {
            monitor.startMonitoring()
        }
        .onDisappear {
            monitor.stopMonitoring()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(monitor.isMonitoring ? "Microphone is live" : "Starting microphone")
        .accessibilityValue("Input level \(Int(monitor.level * 100)) percent")
    }
}

struct MicrophoneWaveformCanvas: View {
    var level: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 45.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                drawBackground(in: &context, size: size)
                drawWaves(in: &context, size: size, time: time)
            }
        }
    }

    private func drawBackground(in context: inout GraphicsContext, size: CGSize) {
        let path = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 16)
        context.fill(
            path,
            with: .linearGradient(
                Gradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: size.height)
            )
        )
    }

    private func drawWaves(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let normalized = max(0.08, level)
        let baseAmplitude = normalized * (size.height / 2.0)

        let waves: [Wave] = [
            Wave(multiplier: 1.0, frequency: 2.2, speed: 1.6, lineWidth: 3, phaseOffset: 0, color: Color.blue),
            Wave(multiplier: 0.65, frequency: 3.4, speed: 1.1, lineWidth: 2.2, phaseOffset: .pi / 2, color: Color.cyan),
            Wave(multiplier: 0.35, frequency: 4.6, speed: 0.9, lineWidth: 1.3, phaseOffset: .pi, color: Color.blue.opacity(0.6))
        ]

        for wave in waves {
            let amplitude = max(1, baseAmplitude * wave.multiplier)
            let phase = CGFloat(time) * wave.speed + wave.phaseOffset
            let path = wavePath(size: size, amplitude: amplitude, phase: phase, frequency: wave.frequency)
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [
                    wave.color.opacity(0.9),
                    wave.color.opacity(0.4)
                ]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: size.width, y: size.height)
            )

            context.stroke(
                path,
                with: shading,
                style: StrokeStyle(
                    lineWidth: wave.lineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }

    private func wavePath(size: CGSize, amplitude: CGFloat, phase: CGFloat, frequency: CGFloat) -> Path {
        var path = Path()
        let width = size.width
        let midY = size.height / 2
        let step = max(1, width / 90)

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

struct ConnectingOverlayView: View {
    let isDisconnecting: Bool

    private var title: String {
        isDisconnecting ? "Ending your call" : "Connecting to your assistant"
    }

    private var subtitle: String {
        if isDisconnecting {
            return "Wrapping up the conversation and saving the transcript."
        }
        return "Setting up the room and dispatching the AI. This only takes a few seconds."
    }

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.4)

            Text(title)
                .font(.headline)
                .foregroundColor(.white)

            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.5))
        .background(.ultraThinMaterial)
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connecting to your assistant. Please wait.")
    }
}

struct ProBadge: View {
    var body: some View {
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

struct ModelPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var settings: UserSettings
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showUpgradeAlert = false
    @State private var showPaywall = false

    private var providerSections: [ModelProviderSection] {
        AIModelProvider.allCases.map { provider in
            ModelProviderSection(provider: provider, models: AIModel.models(for: provider))
        }
    }

    var body: some View {
        let isProActive = subscriptionManager.state.isActive
        let selectModel: (AIModel) -> Void = { model in
            HapticFeedbackService.shared.selection()
            settings.selectedModel = model
            dismiss()
        }
        let requirePro: () -> Void = {
            HapticFeedbackService.shared.warning()
            showUpgradeAlert = true
        }

        return List {
            ForEach(providerSections) { section in
                ModelSectionView(
                    section: section,
                    selectedModel: settings.selectedModel,
                    isProActive: isProActive,
                    onSelect: selectModel,
                    onRequirePro: requirePro
                )
            }
        }
        .alert("Roadtrip Pro required", isPresented: $showUpgradeAlert) {
            Button("Later", role: .cancel) { }
            Button("Upgrade") {
                showPaywall = true
            }
        } message: {
            Text("This model is available for Roadtrip Pro members. Upgrade to unlock it or pick GPT-4o Mini.")
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .navigationTitle("AI Model")
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct ModelProviderSection: Identifiable {
    let provider: AIModelProvider
    let models: [AIModel]

    var id: AIModelProvider { provider }
}

private struct ModelSectionView: View {
    let section: ModelProviderSection
    let selectedModel: AIModel
    let isProActive: Bool
    let onSelect: (AIModel) -> Void
    let onRequirePro: () -> Void

    var body: some View {
        Section(section.provider.displayName) {
            ForEach(section.models, id: \.self) { model in
                ModelSelectionRow(
                    model: model,
                    isSelected: selectedModel == model,
                    isPro: isProActive,
                    onSelect: {
                        onSelect(model)
                    },
                    onRequirePro: onRequirePro
                )
            }
        }
    }
}

struct LanguagePickerView: View {
    @ObservedObject var settings: UserSettings

    private var languages: [VoiceLanguage] {
        TTSVoice.availableLanguages()
    }

    var body: some View {
        List {
            if languages.isEmpty {
                Text("No languages available from the configured voice models.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(languages) { language in
                    Button {
                        HapticFeedbackService.shared.selection()
                        settings.selectedLanguage = language
                    } label: {
                        LanguageRowView(
                            title: language.displayName,
                            subtitle: languageSubtitle(for: language),
                            isSelected: settings.selectedLanguage == language
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.large)
    }

    private func languageSubtitle(for language: VoiceLanguage) -> String {
        let count = TTSVoice.voices(for: language).count
        if count == 1 {
            return "1 voice available"
        } else {
            return "\(count) voices available"
        }
    }
}

struct VoicePickerView: View {
    @ObservedObject var settings: UserSettings
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    
    private var languages: [VoiceLanguage] {
        TTSVoice.availableLanguages()
    }

    private var providerSections: [(provider: TTSProvider, voices: [TTSVoice])] {
        TTSProvider.allCases.compactMap { provider in
            let voices = TTSVoice.voices(for: provider, language: settings.selectedLanguage)
            return voices.isEmpty ? nil : (provider, voices)
        }
    }

    var body: some View {
        List {
            Section {
                if languages.isEmpty {
                    Text("No languages configured. Please update the voice list.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    Picker("Language", selection: $settings.selectedLanguage) {
                        ForEach(languages) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Language")
            } footer: {
                Text("Only voices that support the selected language are shown below.")
            }

            if providerSections.isEmpty {
                Text("No voices are available for \(settings.selectedLanguage.displayName).")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(providerSections, id: \.provider) { section in
                    Section {
                        ForEach(section.voices) { voice in
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
                                Text(section.provider.displayName)
                                if section.voices.first?.requiresPro == true {
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
                            if section.provider == .cartesia {
                                Text("High-quality, natural voices")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .textCase(.none)
                            } else if section.provider == .elevenlabs {
                                Text("Premium, ultra-realistic voices")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .textCase(.none)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if !languages.contains(settings.selectedLanguage), let first = languages.first {
                settings.selectedLanguage = first
            }
        }
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
                Text(voice.language.displayName)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray6))
                    .cornerRadius(4)
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
