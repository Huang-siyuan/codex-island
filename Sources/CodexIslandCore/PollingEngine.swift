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
    public let userInputNotification: CodexLogEvent?
    public let completionNotification: CompletionNotificationRequest?

    public init(
        snapshot: IslandSnapshot,
        completionNotification: CompletionNotificationRequest?,
        userInputNotification: CodexLogEvent? = nil
    ) {
        self.snapshot = snapshot
        self.userInputNotification = userInputNotification
        self.completionNotification = completionNotification
    }
}

public actor PollingEngine {
    private let coordinator: SessionCoordinator
    private let providers: [any SessionProvider]
    private var lastPollAtByProvider: [ProviderKind: Date] = [:]

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
            let now = Date()
            for provider in providers {
                if let lastPollAt = lastPollAtByProvider[provider.kind],
                   now.timeIntervalSince(lastPollAt) < provider.minimumPollingInterval {
                    continue
                }

                let result = try provider.poll()
                lastPollAtByProvider[provider.kind] = now
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
            let completionNotification = coordinator.pendingCompletion.map {
                CompletionNotificationRequest(
                    provider: $0.provider,
                    threadID: $0.threadID,
                    threadTitle: $0.title
                )
            }
            return PollingResult(
                snapshot: snapshot,
                completionNotification: completionNotification,
                userInputNotification: coordinator.pendingUserInput
            )
        } catch {
            return PollingResult(
                snapshot: fallbackSnapshot(errorDescription: error.localizedDescription),
                completionNotification: nil
            )
        }
    }

    public func consumeUserInputNotification(for event: CodexLogEvent) {
        coordinator.consumeUserInputNotification(for: event)
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
