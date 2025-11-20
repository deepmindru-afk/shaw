//
//  CloudKitSyncService.swift
//  Roadtrip
//

import Foundation
import CloudKit

@MainActor
class CloudKitSyncService: ObservableObject {
    static let shared = CloudKitSyncService()

    private let container: CKContainer
    private let privateDatabase: CKDatabase

    @Published var syncStatus: SyncStatus = .idle
    @Published var lastSyncDate: Date?

    enum SyncStatus {
        case idle
        case syncing
        case success
        case error(String)
    }

    private init() {
        self.container = CKContainer.default()
        self.privateDatabase = container.privateCloudDatabase

        // Subscribe to remote changes only if iCloud is available
        Task {
            // Check iCloud availability before subscribing
            if await isICloudAvailable() {
                await subscribeToChanges()
            } else {
                print("⚠️  iCloud not available, skipping CloudKit subscription")
            }
        }
    }

    // MARK: - Session Operations

    func saveSession(_ session: Session) async throws {
        let record = try sessionToRecord(session)
        try await privateDatabase.save(record)
    }

    func fetchSessions() async throws -> [Session] {
        let query = CKQuery(recordType: "Session", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "startTime", ascending: false)]

        let (results, _) = try await privateDatabase.records(matching: query)

        return try results.compactMap { (_, result) in
            switch result {
            case .success(let record):
                return try recordToSession(record)
            case .failure:
                return nil
            }
        }
    }

    func fetchSession(id: String) async throws -> Session? {
        let recordID = CKRecord.ID(recordName: id)

        do {
            let record = try await privateDatabase.record(for: recordID)
            return try recordToSession(record)
        } catch {
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                return nil
            }
            throw error
        }
    }

    func deleteSession(id: String) async throws {
        let recordID = CKRecord.ID(recordName: id)
        try await privateDatabase.deleteRecord(withID: recordID)
    }

    func deleteAllSessions() async throws {
        let sessions = try await fetchSessions()

        for session in sessions {
            try await deleteSession(id: session.id)
        }
    }

    // MARK: - Conversion Helpers

    private func sessionToRecord(_ session: Session) throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: session.id)
        let record = CKRecord(recordType: "Session", recordID: recordID)

        record["userId"] = session.userId as CKRecordValue
        record["startedAt"] = session.startedAt as CKRecordValue
        record["endedAt"] = session.endedAt as CKRecordValue?
        record["context"] = session.context.rawValue as CKRecordValue
        record["loggingEnabledSnapshot"] = session.loggingEnabledSnapshot as CKRecordValue
        record["summaryStatus"] = session.summaryStatus.rawValue as CKRecordValue
        record["durationMinutes"] = session.durationMinutes as CKRecordValue?
        record["summaryError"] = session.summaryError as CKRecordValue?
        record["summaryTitle"] = session.summaryTitle as CKRecordValue?
        record["summarySnippet"] = session.summarySnippet as CKRecordValue?
        record["summaryText"] = session.summaryText as CKRecordValue?

        return record
    }

    private func recordToSession(_ record: CKRecord) throws -> Session {
        guard let userId = record["userId"] as? String,
              let startedAt = record["startedAt"] as? Date,
              let contextString = record["context"] as? String,
              let context = Session.SessionContext(rawValue: contextString),
              let loggingEnabledSnapshot = record["loggingEnabledSnapshot"] as? Bool,
              let summaryStatusString = record["summaryStatus"] as? String,
              let summaryStatus = Session.SummaryStatus(rawValue: summaryStatusString) else {
            throw CloudKitError.invalidRecord
        }

        let endedAt = record["endedAt"] as? Date
        let durationMinutes = record["durationMinutes"] as? Int
        let summaryError = record["summaryError"] as? String
        let summaryTitle = record["summaryTitle"] as? String
        let summarySnippet = record["summarySnippet"] as? String
        let summaryText = record["summaryText"] as? String

        return Session(
            id: record.recordID.recordName,
            userId: userId,
            context: context,
            startedAt: startedAt,
            endedAt: endedAt,
            loggingEnabledSnapshot: loggingEnabledSnapshot,
            summaryStatus: summaryStatus,
            summaryError: summaryError,
            summaryTitle: summaryTitle,
            summarySnippet: summarySnippet,
            summaryText: summaryText,
            durationMinutes: durationMinutes
        )
    }

    // MARK: - Subscriptions for Real-time Sync

    private func subscribeToChanges() async {
        // Double-check iCloud availability before subscribing
        guard await isICloudAvailable() else {
            print("⚠️  Cannot subscribe to CloudKit changes: iCloud not available")
            return
        }
        
        let subscriptionID = "session-changes"
        let subscription = CKQuerySubscription(
            recordType: "Session",
            predicate: NSPredicate(value: true),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        do {
            try await privateDatabase.save(subscription)
            print("✅ Successfully subscribed to CloudKit changes")
        } catch {
            // Handle specific CloudKit errors
            if let ckError = error as? CKError {
                switch ckError.code {
                case .notAuthenticated:
                    print("⚠️  CloudKit not authenticated: User needs to sign in to iCloud in Settings")
                case .accountTemporarilyUnavailable:
                    print("⚠️  CloudKit account temporarily unavailable")
                case .networkUnavailable:
                    print("⚠️  CloudKit network unavailable")
                default:
                    print("⚠️  Failed to subscribe to CloudKit changes: \(ckError.localizedDescription)")
                }
            } else {
                print("⚠️  Failed to subscribe to CloudKit changes: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Account Status

    func checkAccountStatus() async throws -> CKAccountStatus {
        return try await container.accountStatus()
    }

    func isICloudAvailable() async -> Bool {
        do {
            let status = try await checkAccountStatus()
            return status == .available
        } catch {
            return false
        }
    }
}

enum CloudKitError: LocalizedError {
    case invalidRecord
    case notAvailable
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidRecord:
            return "Invalid CloudKit record"
        case .notAvailable:
            return "iCloud is not available. Please sign in to iCloud in Settings."
        case .unauthorized:
            return "Not authorized to access iCloud"
        }
    }
}
