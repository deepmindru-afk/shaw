//
//  SettingsScreen.swift
//  Roadtrip
//

import SwiftUI
import AVFoundation
import CloudKit

private struct RetentionOption: Identifiable {
    let value: Int
    let title: String
    let isPro: Bool

    var id: Int { value }
}

struct SettingsScreen: View {
    @ObservedObject private var settings = UserSettings.shared
    @State private var appCoordinator = AppCoordinator.shared
    @State private var showDeleteAccountConfirmation = false
    @State private var showDeleteSuccess = false
    @State private var showDeleteAccountError = false
    @State private var deleteAccountErrorMessage: String?
    @State private var usageStats: UsageStatsResponse?
    @State private var isLoadingUsage = false
    @State private var usageError: String?
    @StateObject private var hybridLogger = HybridSessionLogger.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var syncStatus: String?
    @State private var isRefreshing = false
    @State private var showRestoreSuccess = false
    @State private var showRestoreError = false
    @State private var restoreErrorMessage: String?
    @State private var showPaywall = false
    @State private var showCapabilitiesInfo = false
    @State private var lastAllowedRetentionDays = UserSettings.shared.retentionDays
    @State private var showRetentionUpgradeAlert = false
    @State private var showSignOutConfirmation = false

    private let retentionOptions: [RetentionOption] = [
        RetentionOption(value: 0, title: "Never delete", isPro: true),
        RetentionOption(value: 7, title: "Delete after 7 days", isPro: false),
        RetentionOption(value: 30, title: "Delete after 30 days", isPro: false),
        RetentionOption(value: 90, title: "Delete after 90 days", isPro: true),
        RetentionOption(value: 180, title: "Delete after 180 days", isPro: true),
        RetentionOption(value: 365, title: "Delete after 365 days", isPro: true)
    ]
    private let freeRetentionDefaultDays = 30
    

    var body: some View {
        Form {
            accountSection
            subscriptionSection
            cloudBackupSection
            assistantCapabilitiesSection
            dataRetentionSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .alert("Delete Account", isPresented: $showDeleteAccountConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Account", role: .destructive) {
                deleteAccount()
            }
        } message: {
            Text("Are you sure you want to delete your account? This will permanently remove all your data, sessions, and subscriptions. This action cannot be undone.")
        }
        .alert("Account Deleted", isPresented: $showDeleteSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your account and all associated data have been deleted.")
        }
        .alert("Deletion Failed", isPresented: $showDeleteAccountError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteAccountErrorMessage ?? "Failed to delete account. Please try again.")
        }
        .alert("Restore Complete", isPresented: $showRestoreSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your sessions have been successfully restored from iCloud.")
        }
        .alert("Restore Failed", isPresented: $showRestoreError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreErrorMessage ?? "Failed to restore sessions from iCloud. Please try again.")
        }
        .alert("Sign Out", isPresented: $showSignOutConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                performSignOut()
            }
        } message: {
            Text("You will need to sign in with Apple again to access your sessions.")
        }
        .alert("Assistant Capabilities", isPresented: $showCapabilitiesInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Tool calling allows the assistant to use external capabilities like web search. When enabled, the assistant can search the web for real-time information, news, and facts using Perplexity.")
        }
        .onAppear {
            enforceRetentionAccess()
        }
        .onChange(of: subscriptionManager.state) { _, _ in
            enforceRetentionAccess()
        }
        .task {
            loadUsageStats()
            await checkSyncStatus()
        }
        .refreshable {
            loadUsageStats()
            await checkSyncStatus()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    private var isProUser: Bool {
        subscriptionManager.state.isActive
    }

    @ViewBuilder
    private var accountSection: some View {
        Section {
            HStack {
                Text("Status")
                Spacer()
                Text(settings.isSignedIn ? "Signed in" : "Not signed in")
                    .font(.subheadline)
                    .foregroundColor(settings.isSignedIn ? .green : .orange)
            }

            if let identifier = formattedAppleIdentifier {
                HStack {
                    Text("Apple Identifier")
                    Spacer()
                    Text(identifier)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Button(role: .destructive) {
                showSignOutConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Sign Out")
                }
            }
            .disabled(!settings.isSignedIn)
        } header: {
            Text("Account")
        } footer: {
            Text("Signing out removes access to your synced sessions on this device until you sign in with Apple again.")
        }
    }

    @ViewBuilder
    private var subscriptionSection: some View {
        Section {
            subscriptionStatusRow
            minuteTrackerView

            if subscriptionManager.state.status == .inactive {
                Button(action: { showPaywall = true }) {
                    HStack {
                        Image(systemName: "star.fill")
                        Text("Upgrade to Pro")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 12)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }

            Button(action: restoreSubscription) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Restore Purchases")
                }
            }
            .disabled(subscriptionManager.isLoading)
            .padding(.vertical, 12)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        } header: {
            Text("Subscription")
        }
    }

    private var subscriptionStatusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: subscriptionManager.state.isActive ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(subscriptionManager.state.isActive ? .green : .orange)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text(subscriptionManager.state.displayStatus)
                    .font(.headline)

                Text("Subscription Status")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    @ViewBuilder
    private var minuteTrackerView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Minute Tracker (per month)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            if isLoadingUsage {
                HStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading usage...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else if let stats = usageStats {
                usageStatsView(stats: stats)
            } else if let error = usageError {
                usageErrorView(error: error)
            } else {
                Button(action: loadUsageStats) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Load Usage Statistics")
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }

    @ViewBuilder
    private func usageStatsView(stats: UsageStatsResponse) -> some View {
        if let remaining = stats.remainingMinutes, let limit = stats.monthlyLimit {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(stats.usedMinutes) / \(limit) minutes this month")
                        .font(.headline)
                        .foregroundColor(remaining < 10 ? .red : .primary)

                    Text("\(remaining) remaining this month")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemGray5))
                        .frame(height: 8)

                    Capsule()
                        .fill(remaining < 10 ? Color.red : Color.blue)
                        .frame(
                            width: min(geometry.size.width, geometry.size.width * CGFloat(stats.usedMinutes) / CGFloat(limit)),
                            height: 8
                        )
                }
            }
            .frame(height: 8)
        } else if stats.monthlyLimit == nil {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(stats.usedMinutes) minutes used this month")
                        .font(.headline)

                    Text("Unlimited plan")
                        .font(.caption)
                        .foregroundColor(.green)
                }

                Spacer()

                Image(systemName: "infinity")
                    .foregroundColor(.green)
                    .font(.title3)
            }
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(stats.usedMinutes) minutes used this month")
                        .font(.headline)
                }

                Spacer()
            }
        }
    }

    private func usageErrorView(error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Failed to load usage")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button("Retry", action: loadUsageStats)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private var cloudBackupSection: some View {
        Section {
            HStack {
                Image(systemName: syncStatus?.contains("Syncing via iCloud") == true ? "checkmark.icloud" : "icloud.slash")
                    .foregroundColor(syncStatus?.contains("Syncing via iCloud") == true ? .green : .orange)
                    .imageScale(.large)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Sync Status")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let status = syncStatus {
                        Text(status)
                            .font(.body)
                            .foregroundColor(status.contains("Syncing via iCloud") ? .primary : .secondary)
                    } else {
                        Text("Checking...")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 4)

            Button(action: restoreFromiCloud) {
                HStack {
                    if isRefreshing {
                        ProgressView()
                        Text("Restoring...")
                    } else {
                        Image(systemName: "arrow.clockwise.icloud")
                        Text("Restore from iCloud")
                    }
                }
            }
            .disabled(isRefreshing || syncStatus?.contains("unavailable") == true)
        } header: {
            Text("Cloud Backup")
        } footer: {
            Text("Sessions automatically sync across all your devices signed into the same iCloud account. Use restore to manually fetch the latest data from iCloud.")
        }
    }

    @ViewBuilder
    private var assistantCapabilitiesSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { settings.toolCallingEnabled },
                set: { newValue in
                    HapticFeedbackService.shared.light()
                    settings.toolCallingEnabled = newValue
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable Tool Calling")
                        .font(.body)
                    Text("Allow assistant to use external tools and capabilities")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if settings.toolCallingEnabled {
                Toggle(isOn: Binding(
                    get: { settings.webSearchEnabled },
                    set: { newValue in
                        HapticFeedbackService.shared.light()
                        settings.webSearchEnabled = newValue
                    }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Web Search")
                            .font(.body)
                        Text("Search the web for current information, news, and facts")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        } header: {
            HStack(spacing: 4) {
                Text("Assistant Capabilities")
                Button(action: { showCapabilitiesInfo = true }) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } footer: {
            if settings.toolCallingEnabled {
                Text("The assistant can use Perplexity to search the web for real-time information when needed.")
            } else {
                Text("Tool calling is disabled. The assistant will rely only on its built-in knowledge.")
            }
        }
    }

    @ViewBuilder
    private var dataRetentionSection: some View {
        Section {
            NavigationLink {
                retentionPicker
                    .navigationTitle("Retention Period")
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                HStack {
                    Text("Retention Period")
                    Spacer()
                    Text(retentionPeriodDisplayText)
                        .foregroundColor(.secondary)
                }
            }

            retentionDescription

            Button(role: .destructive, action: { showDeleteAccountConfirmation = true }) {
                HStack {
                    Image(systemName: "person.crop.circle.badge.xmark")
                    Text("Delete Account")
                }
            }
        } header: {
            HStack(spacing: 4) {
                Text("Data Retention")
                Button(action: {}) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .help("Automatically delete old sessions to save storage space")
            }
        } footer: {
            Text("This will permanently delete your account and all associated data.")
        }
    }

    private var retentionPicker: some View {
        List {
            ForEach(retentionOptions) { option in
                Button {
                    handleRetentionSelectionChange(option.value)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(option.title)
                                    .foregroundColor(.primary)

                                if option.isPro {
                                    ProBadge()
                                }
                            }
                            if option.value > 0 {
                                Text("Deletes after \(option.value) days")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Keeps all sessions")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        if settings.retentionDays == option.value {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                                .fontWeight(.bold)
                        }
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .alert("Roadtrip Pro required", isPresented: $showRetentionUpgradeAlert) {
            Button("Later", role: .cancel) {}
            Button("Upgrade") {
                showPaywall = true
            }
        } message: {
            Text("Longer retention periods are available for Roadtrip Pro members. Upgrade to unlock Never delete and 90+ day options.")
        }
    }

    @ViewBuilder
    private var retentionDescription: some View {
        if settings.retentionDays == 0 {
            Text("Sessions will never be automatically deleted.")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            Text("Sessions older than \(settings.retentionDays) days will be automatically deleted.")
                .font(.caption)
                .foregroundColor(.secondary)
        }

        if !isProUser {
            Text("Upgrade to Pro to unlock 90+ day retention and the Never delete option.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func isProRetentionOption(_ days: Int) -> Bool {
        days == 0 || days >= 90
    }

    private func handleRetentionSelectionChange(_ newValue: Int) {
        if !isProUser && isProRetentionOption(newValue) {
            HapticFeedbackService.shared.warning()
            showRetentionUpgradeAlert = true
            settings.retentionDays = lastAllowedRetentionDays
            return
        }

        if settings.retentionDays != newValue {
            HapticFeedbackService.shared.selection()
            settings.retentionDays = newValue
        }
        lastAllowedRetentionDays = newValue
    }

    private func enforceRetentionAccess() {
        if !isProUser && isProRetentionOption(settings.retentionDays) {
            settings.retentionDays = freeRetentionDefaultDays
            lastAllowedRetentionDays = freeRetentionDefaultDays
        } else {
            lastAllowedRetentionDays = settings.retentionDays
        }
    }

    private func openSubscriptionManagement() {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        UIApplication.shared.open(url)
    }

    private func restoreSubscription() {
        Task {
            do {
                try await subscriptionManager.restore()
                await MainActor.run {
                    showRestoreSuccess = true
                    restoreErrorMessage = nil
                }
            } catch {
                await MainActor.run {
                    // Provide a more helpful error message
                    if let subscriptionError = error as? SubscriptionError {
                        restoreErrorMessage = subscriptionError.localizedDescription
                    } else {
                        restoreErrorMessage = "Failed to restore purchases: \(error.localizedDescription)"
                    }
                    showRestoreError = true
                }
            }
        }
    }

    

    private func loadUsageStats() {
        isLoadingUsage = true
        usageError = nil

        Task {
            do {
                let stats = try await SessionLogger.shared.getUsageStats()
                await MainActor.run {
                    usageStats = stats
                    isLoadingUsage = false
                    usageError = nil
                }
            } catch {
                await MainActor.run {
                    // Extract a user-friendly error message
                    let errorMessage: String
                    if let sessionError = error as? SessionLoggerError {
                        switch sessionError {
                        case .serverError(let statusCode, let message):
                            if statusCode == 502 {
                                errorMessage = "Server temporarily unavailable. Usage stats will be available when the server is back online."
                            } else {
                                errorMessage = "Server error (\(statusCode)): \(message)"
                            }
                        case .unauthorized:
                            errorMessage = "Authentication required. Please restart the app."
                        default:
                            errorMessage = sessionError.localizedDescription
                        }
                    } else {
                        errorMessage = error.localizedDescription
                    }
                    
                    usageError = errorMessage
                    isLoadingUsage = false
                    // Don't clear existing stats if we have them - show error but keep old data
                }
            }
        }
    }

    private var retentionPeriodDisplayText: String {
        switch settings.retentionDays {
        case 0:
            return "Never delete"
        case 7:
            return "Delete after 7 days"
        case 30:
            return "Delete after 30 days"
        case 90:
            return "Delete after 90 days"
        case 180:
            return "Delete after 180 days"
        case 365:
            return "Delete after 365 days"
        default:
            return "Delete after \(settings.retentionDays) days"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private var formattedAppleIdentifier: String? {
        guard let raw = AuthService.shared.appleUserID else { return nil }
        let prefix = raw.prefix(6)
        let suffix = raw.suffix(4)
        return "\(prefix)…\(suffix)"
    }

    private func performSignOut() {
        AuthService.shared.logout()
        settings.isSignedIn = false

        Task { @MainActor in
            hybridLogger.sessions = []
            hybridLogger.error = nil
        }
    }

    private func deleteAccount() {
        Task {
            do {
                try await AuthService.shared.deleteAccount()
                await MainActor.run {
                    showDeleteSuccess = true
                    settings.isSignedIn = false
                    hybridLogger.sessions = []
                }
            } catch {
                await MainActor.run {
                    deleteAccountErrorMessage = error.localizedDescription
                    showDeleteAccountError = true
                }
            }
        }
    }

    private func checkSyncStatus() async {
        let status = await hybridLogger.checkSyncStatus()
        await MainActor.run {
            syncStatus = status
        }
    }

    private func restoreFromiCloud() {
        isRefreshing = true
        restoreErrorMessage = nil

        Task {
            // Check if iCloud is available first
            let cloudKitAvailable = await CloudKitSyncService.shared.isICloudAvailable()
            
            if !cloudKitAvailable {
                await MainActor.run {
                    isRefreshing = false
                    restoreErrorMessage = "iCloud is not available. Please sign in to iCloud in Settings."
                    showRestoreError = true
                }
                return
            }
            
            // Try to load sessions directly from CloudKit (bypass backend fallback)
            do {
                let cloudKitSessions = try await CloudKitSyncService.shared.fetchSessions()
                // Convert to SessionListItem format
                let sessionListItems = cloudKitSessions.map { SessionListItem.from(session: $0) }
                
                await MainActor.run {
                    hybridLogger.sessions = sessionListItems
                    hybridLogger.error = nil // Clear any previous errors
                    isRefreshing = false
                    showRestoreSuccess = true
                    restoreErrorMessage = nil
                }
            } catch {
                await MainActor.run {
                    isRefreshing = false
                    // Provide a clear error message for CloudKit failures
                    if let ckError = error as? CKError {
                        switch ckError.code {
                        case .notAuthenticated:
                            restoreErrorMessage = "Please sign in to iCloud in Settings."
                        case .networkUnavailable:
                            restoreErrorMessage = "Network unavailable. Please check your internet connection."
                        default:
                            restoreErrorMessage = "Failed to restore from iCloud: \(ckError.localizedDescription)"
                        }
                    } else {
                        restoreErrorMessage = "Failed to restore from iCloud: \(error.localizedDescription)"
                    }
                    showRestoreError = true
                }
            }
        }
    }
}

#Preview {
    SettingsScreen()
}
