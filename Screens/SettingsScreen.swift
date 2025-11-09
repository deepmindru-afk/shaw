//
//  SettingsScreen.swift
//  AI Voice Copilot
//

import SwiftUI

struct SettingsScreen: View {
    @ObservedObject var settings = UserSettings.shared
    @ObservedObject var appCoordinator = AppCoordinator.shared
    @State private var showDeleteAllConfirmation = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enable Logging & Summaries", isOn: $settings.loggingEnabled)
                    
                    if settings.loggingEnabled {
                        Text("Your assistant calls will be recorded and summarized for your benefit.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Voice-only mode: No recording or history will be saved.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("You can change this setting at any time. When disabled, calls will still work but no history will be saved.")
                }
                
                Section {
                    Stepper("\(settings.retentionDays) days", value: $settings.retentionDays, in: 7...365)
                    Text("Sessions older than this will be automatically deleted.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Data Retention")
                }
                
                Section {
                    Button(role: .destructive, action: {
                        showDeleteAllConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete All History")
                        }
                    }
                } header: {
                    Text("Data Management")
                } footer: {
                    Text("This will permanently delete all your session history and summaries.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        appCoordinator.navigate(to: .home)
                    }) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                }
            }
            .alert("Delete All History", isPresented: $showDeleteAllConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete All", role: .destructive) {
                    deleteAllSessions()
                }
            } message: {
                Text("Are you sure you want to delete all your session history? This action cannot be undone.")
            }
        }
    }
    
    private func deleteAllSessions() {
        Task {
            do {
                try await SessionLogger.shared.deleteAllSessions()
                await MainActor.run {
                    // Show success message or navigate back
                }
            } catch {
                // Handle error
                print("Failed to delete all sessions: \(error)")
            }
        }
    }
}

#Preview {
    SettingsScreen()
}

