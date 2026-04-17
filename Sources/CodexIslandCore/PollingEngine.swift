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
    public let completionNotification: CompletionNotificationRequest?

    public init(snapshot: IslandSnapshot, completionNotification: CompletionNotificationRequest?) {
        self.snapshot = snapshot
        self.completionNotification = completionNotification
    }
}

public actor PollingEngine {
    private let coordinator: SessionCoordinator
    private let providers: [any SessionProvider]

    public init(
        coordinator: SessionCoordinator = SessionCoordinator(),
        providers: [any SessionProvider] = [
            CodexSessionProvider(),
            ClaudeCodeSessionProvider(),
            CodeBuddySessionProvider(),
        ]
    ) {
        self.coordinator = coordinator
        self.providers = providers
    }

    public func pollOnce() -> PollingResult {
        do {
            for provider in providers {
                let result = try provider.poll()
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
            return PollingResult(snapshot: snapshot, completionNotification: completionNotification)
        } catch {
            return PollingResult(
                snapshot: fallbackSnapshot(errorDescription: error.localizedDescription),
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
}
