//
//  SessionsListScreen.swift
//  AI Voice Copilot
//

import SwiftUI

struct SessionsListScreen: View {
    @State private var sessions: [SessionListItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @ObservedObject var appCoordinator = AppCoordinator.shared
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading sessions...")
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            loadSessions()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else if sessions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.badge.questionmark")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No sessions yet")
                            .font(.headline)
                        Text("Start a call to create your first session")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    List(sessions) { session in
                        NavigationLink(value: session.id) {
                            SessionRow(session: session) {}
                        }
                    }
                }
            }
            .navigationTitle("Sessions")
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
        }
            .navigationDestination(for: String.self) { sessionID in
                SessionDetailScreen(sessionID: sessionID)
            }
            .onAppear {
                loadSessions()
            }
    }
    
    private func loadSessions() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let fetchedSessions = try await SessionLogger.shared.fetchSessions()
                await MainActor.run {
                    self.sessions = fetchedSessions
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load sessions: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
}

struct SessionRow: View {
    let session: SessionListItem
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Text(session.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                if !session.summarySnippet.isEmpty {
                    Text(session.summarySnippet)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                HStack {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text(formatDate(session.startedAt))
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    SessionsListScreen()
}

