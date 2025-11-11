//
//  HomeScreen.swift
//  AI Voice Copilot
//

import SwiftUI

struct HomeScreen: View {
    @ObservedObject var callCoordinator = AssistantCallCoordinator.shared
    @ObservedObject var appCoordinator = AppCoordinator.shared
    @State private var showErrorAlert = false
    
    var body: some View {
        NavigationStack(path: $appCoordinator.navigationPath) {
            VStack(spacing: 32) {
                Spacer()
                
                VStack(spacing: 16) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.blue)
                    
                    Text("AI Voice Copilot")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Talk to your AI assistant hands-free")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
                
                VStack(spacing: 16) {
                    CallAssistantButton()
                    
                    if callCoordinator.callState == .connected {
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("Assistant call may be recorded for your summaries.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }
                    
                    if let errorMessage = callCoordinator.errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }
                }
                
                Spacer()
            }
            .padding()
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
    }
}

struct CallAssistantButton: View {
    @ObservedObject var callCoordinator = AssistantCallCoordinator.shared

    var body: some View {
        Button(action: {
            if callCoordinator.callState == .idle {
                let enableLogging = UserSettings.shared.loggingEnabled
                callCoordinator.startAssistantCall(context: "phone", enableLogging: enableLogging)
            } else {
                callCoordinator.endAssistantCall()
            }
        }) {
            HStack {
                Image(systemName: callCoordinator.callState == .idle ? "phone.fill" : "phone.down.fill")
                    .font(.title2)
                Text(callCoordinator.callState == .idle ? "Call Assistant" : "End Call")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(callCoordinator.callState == .idle ? Color.blue : Color.red)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(callCoordinator.callState == .connecting || callCoordinator.callState == .disconnecting)
    }
}

#Preview {
    HomeScreen()
}

