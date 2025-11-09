//
//  SessionDetailScreen.swift
//  AI Voice Copilot
//

import SwiftUI

struct SessionDetailScreen: View {
    let sessionID: String
    @State private var summary: SessionSummary?
    @State private var turns: [Turn] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    @ObservedObject var appCoordinator = AppCoordinator.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if isLoading {
                    ProgressView("Loading session details...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            loadSessionDetails()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    if let summary = summary {
                        SummarySection(summary: summary)
                    }
                    
                    if !turns.isEmpty {
                        TranscriptSection(turns: turns)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Session Details")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(role: .destructive, action: {
                        showDeleteConfirmation = true
                    }) {
                        Label("Delete Session", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Delete Session", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteSession()
            }
        } message: {
            Text("Are you sure you want to delete this session? This action cannot be undone.")
        }
        .onAppear {
            loadSessionDetails()
        }
    }
    
    private func loadSessionDetails() {
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let (fetchedSummary, fetchedTurns) = try await SessionLogger.shared.fetchSessionDetail(sessionID: sessionID)
                await MainActor.run {
                    self.summary = fetchedSummary
                    self.turns = fetchedTurns
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load session: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func deleteSession() {
        Task {
            do {
                try await SessionLogger.shared.deleteSession(sessionID: sessionID)
                await MainActor.run {
                    appCoordinator.navigateBack()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to delete session: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct SummarySection: View {
    let summary: SessionSummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Summary")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(summary.title)
                .font(.headline)
            
            Text(summary.summaryText)
                .font(.body)
            
            if !summary.actionItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Action Items")
                        .font(.headline)
                    ForEach(summary.actionItems, id: \.self) { item in
                        HStack(alignment: .top) {
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.blue)
                            Text(item)
                                .font(.subheadline)
                        }
                    }
                }
            }
            
            if !summary.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(summary.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(12)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct TranscriptSection: View {
    let turns: [Turn]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcript")
                .font(.title2)
                .fontWeight(.bold)
            
            ForEach(turns) { turn in
                TranscriptBubble(turn: turn)
            }
        }
    }
}

struct TranscriptBubble: View {
    let turn: Turn
    
    var body: some View {
        HStack {
            if turn.speaker == .user {
                Spacer()
            }
            
            VStack(alignment: turn.speaker == .user ? .trailing : .leading, spacing: 4) {
                Text(turn.text)
                    .padding()
                    .background(turn.speaker == .user ? Color.blue : Color(.systemGray5))
                    .foregroundColor(turn.speaker == .user ? .white : .primary)
                    .cornerRadius(16)
                
                Text(formatTime(turn.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: turn.speaker == .user ? .trailing : .leading)
            
            if turn.speaker == .assistant {
                Spacer()
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        SessionDetailScreen(sessionID: "test-id")
    }
}

