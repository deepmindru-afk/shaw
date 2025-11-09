//
//  OnboardingScreen.swift
//  AI Voice Copilot
//

import SwiftUI

struct OnboardingScreen: View {
    @ObservedObject var settings = UserSettings.shared
    @State private var selectedOption: LoggingOption?
    
    enum LoggingOption {
        case enabled
        case disabled
    }
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)
                
                Text("Welcome to AI Voice Copilot")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text("Your AI assistant for hands-free conversations while driving")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
            
            VStack(spacing: 16) {
                Text("Recording & Summaries")
                    .font(.headline)
                
                Text("Your assistant calls can be recorded and summarized for your benefit.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(spacing: 12) {
                    Button(action: {
                        selectedOption = .enabled
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Allow logging & summaries")
                                    .font(.headline)
                                Text("Save conversation history and get AI-generated summaries")
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
                        .padding()
                        .background(selectedOption == .enabled ? Color.blue.opacity(0.1) : Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        selectedOption = .disabled
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Don't allow (voice-only)")
                                    .font(.headline)
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
                        .padding()
                        .background(selectedOption == .disabled ? Color.blue.opacity(0.1) : Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
            }
            
            Spacer()
            
            Button(action: {
                if let option = selectedOption {
                    settings.loggingEnabled = (option == .enabled)
                    settings.hasSeenOnboarding = true
                }
            }) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(selectedOption != nil ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(selectedOption == nil)
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }
}

#Preview {
    OnboardingScreen()
}

