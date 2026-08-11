import Foundation

public struct CompletionNotificationRequest: Sendable, Equatable {
    public let provider: ProviderKind
    public let threadID: String
    public let threadTitle: String

    public init(provider: ProviderKind, threadID: String, threadTitle: String) {
        self.provider = provider
        self.threadID = threadID
        self.threadTitle = threadTitle
    }
}

public struct PollingResult: Sendable, Equatable {
    public let snapshot: IslandSnapshot
    public let usageSnapshot: LocalUsageSnapshot?
    public let completionNotification: CompletionNotificationRequest?

    public init(
        snapshot: IslandSnapshot,
        usageSnapshot: LocalUsageSnapshot?,
        completionNotification: CompletionNotificationRequest?
    ) {
        self.snapshot = snapshot
        self.usageSnapshot = usageSnapshot
        self.completionNotification = completionNotification
    }
}

public actor PollingEngine {
    private let coordinator: SessionCoordinator
    private let providers: [any SessionProvider]
    private let usageSnapshotReader: LocalUsageSnapshotReader
    private let usageRefreshInterval: TimeInterval
    private let now: () -> Date
    private var cachedUsageSnapshot: LocalUsageSnapshot?
    private var lastUsageRefreshAt: Date?

    public init(
        coordinator: SessionCoordinator = SessionCoordinator(),
        usageSnapshotReader: LocalUsageSnapshotReader = LocalUsageSnapshotReader(),
        usageRefreshInterval: TimeInterval = 20,
        now: @escaping () -> Date = Date.init,
        providers: [any SessionProvider] = [
            CodexSessionProvider(),
            ClaudeCodeSessionProvider(),
            CodeBuddySessionProvider(),
        ]
    ) {
        self.coordinator = coordinator
        self.usageSnapshotReader = usageSnapshotReader
        self.usageRefreshInterval = usageRefreshInterval
        self.now = now
        self.providers = providers
    }

    public func pollOnce() -> PollingResult {
        let usageSnapshot = refreshUsageSnapshotIfNeeded()
        do {
            for provider in providers {
                let result = try provider.poll()
                coordinator.pruneSessions(
                    for: provider.kind,
                    keeping: Set(result.threadSnapshots.map(\.sessionKey))
                )
                coordinator.apply(threadSnapshots: result.threadSnapshots)
                coordinator.apply(messagePreviews: result.messagePreviews)
                coordinator.apply(logEvents: result.logEvents)

                let timestamps = Dictionary(grouping: result.logEvents, by: \.sessionKey)
                    .compactMapValues { events in
                        events.map(\.timestamp).max()
                    }

                for snapshot in result.threadSnapshots {
                    if let timestamp = timestamps[snapshot.sessionKey] ?? result.messagePreviews
                        .filter({ $0.sessionKey == snapshot.sessionKey })
                        .map(\.timestamp)
                        .max() {
                        coordinator.recordActivity(
                            provider: snapshot.provider,
                            threadID: snapshot.threadID,
                            timestamp: timestamp
                        )
                    }
                }
            }

            let snapshot = coordinator.currentSnapshot
            let completionNotification = snapshot.shouldNotifyCompletion
                ? snapshot.activeProvider.flatMap { provider in
                    snapshot.primaryThreadID.map {
                        CompletionNotificationRequest(
                            provider: provider,
                            threadID: $0,
                            threadTitle: snapshot.threadTitle
                        )
                    }
                }
                : nil
            return PollingResult(
                snapshot: snapshot,
                usageSnapshot: usageSnapshot,
                completionNotification: completionNotification
            )
        } catch {
            return PollingResult(
                snapshot: fallbackSnapshot(errorDescription: error.localizedDescription),
                usageSnapshot: cachedUsageSnapshot,
                completionNotification: nil
            )
        }
    }

    public func consumeCompletionNotification(for provider: ProviderKind, threadID: String) {
        coordinator.consumeCompletionNotification(for: provider, threadID: threadID)
    }

    public func consumeCompletionNotification(for threadID: String) {
        coordinator.consumeCompletionNotification(for: threadID)
    }

    private func fallbackSnapshot(errorDescription: String) -> IslandSnapshot {
        IslandSnapshot(
            activeProvider: nil,
            primaryThreadID: nil,
            threadTitle: "Codex Island",
            statusText: "Waiting for AI tools",
            latestToolSummary: errorDescription,
            sourceLabel: "AI Tools",
            activeSessionCount: 0,
            sessionPreviews: [],
            shouldNotifyCompletion: false
        )
    }

    private func refreshUsageSnapshotIfNeeded() -> LocalUsageSnapshot? {
        let currentTime = now()
        let shouldRefresh: Bool

        if cachedUsageSnapshot == nil {
            shouldRefresh = true
        } else if let lastUsageRefreshAt {
            shouldRefresh = currentTime.timeIntervalSince(lastUsageRefreshAt) >= usageRefreshInterval
        } else {
            shouldRefresh = true
        }

        if shouldRefresh {
            cachedUsageSnapshot = usageSnapshotReader.readSnapshot(days: 30)
            lastUsageRefreshAt = currentTime
        }

        return cachedUsageSnapshot
    }
}
