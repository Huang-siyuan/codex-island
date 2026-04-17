import Foundation

public final class SessionCoordinator {
    private let sessionPreviewLimit = 3
    private var threadSnapshots: [String: ThreadSnapshot] = [:]
    private var latestLogEvents: [String: CodexLogEvent] = [:]
    private var latestActivityTimestamps: [String: Date] = [:]
    private var latestUserPreviews: [String: SessionMessagePreview] = [:]
    private var latestAssistantPreviews: [String: SessionMessagePreview] = [:]
    private var completionCandidates: [String: Date] = [:]
    private var deliveredCompletionCandidates: [String: Date] = [:]
    private let now: () -> Date
    private let completionIdleThreshold: TimeInterval
    private let completionConfirmationThreshold: TimeInterval

    public init(
        now: @escaping () -> Date = Date.init,
        completionIdleThreshold: TimeInterval = 4,
        completionConfirmationThreshold: TimeInterval = 2
    ) {
        self.now = now
        self.completionIdleThreshold = completionIdleThreshold
        self.completionConfirmationThreshold = completionConfirmationThreshold
    }

    public func apply(threadSnapshots: [ThreadSnapshot]) {
        for snapshot in threadSnapshots {
            self.threadSnapshots[snapshot.sessionKey] = snapshot
        }
    }

    public func apply(logEvents: [CodexLogEvent]) {
        for event in logEvents {
            let key = event.sessionKey
            latestLogEvents[key] = event
            latestActivityTimestamps[key] = max(latestActivityTimestamps[key] ?? .distantPast, event.timestamp)

            switch event.kind {
            case .responseCompleted:
                if completionCandidates[key] == nil {
                    completionCandidates[key] = event.timestamp
                }
            case .responseCreated, .responseInProgress, .toolStarted, .toolUpdated, .toolCompleted:
                if let completionCandidate = completionCandidates[key], event.timestamp >= completionCandidate {
                    completionCandidates.removeValue(forKey: key)
                    deliveredCompletionCandidates.removeValue(forKey: key)
                }
            }
        }
    }

    public func apply(messagePreviews: [SessionMessagePreview]) {
        for preview in messagePreviews {
            let key = preview.sessionKey
            switch preview.author {
            case .user:
                if shouldReplacePreview(current: latestUserPreviews[key], replacement: preview) {
                    latestUserPreviews[key] = preview
                }
            case .assistant:
                if shouldReplacePreview(current: latestAssistantPreviews[key], replacement: preview) {
                    latestAssistantPreviews[key] = preview
                }
            }
        }
    }

    public func recordActivity(provider: ProviderKind, threadID: String, timestamp: Date) {
        latestActivityTimestamps[SessionIdentity.key(provider: provider, threadID: threadID)] = max(
            latestActivityTimestamps[SessionIdentity.key(provider: provider, threadID: threadID)] ?? .distantPast,
            timestamp
        )
    }

    public func recordActivity(threadID: String, timestamp: Date) {
        recordActivity(provider: .codex, threadID: threadID, timestamp: timestamp)
    }

    public func consumeCompletionNotification(for provider: ProviderKind, threadID: String) {
        let key = SessionIdentity.key(provider: provider, threadID: threadID)
        guard let completionCandidate = completionCandidates[key] else {
            return
        }
        deliveredCompletionCandidates[key] = completionCandidate
    }

    public func consumeCompletionNotification(for threadID: String) {
        consumeCompletionNotification(for: .codex, threadID: threadID)
    }

    public var currentSnapshot: IslandSnapshot {
        let primary = primarySnapshot()
        let primaryKey = primary?.sessionKey
        let event = primaryKey.flatMap { latestLogEvents[$0] }
        let recentActivity = primary.map(activityDate(for:))
        let activeProvider = primary?.provider
        let providerSnapshots = activeProvider.map(snapshots(for:)) ?? []
        let didConfirmCompletion = primary.map { isCompletionConfirmed(for: $0.sessionKey) } ?? false
        let sessionPreviews = providerSnapshots
            .sorted(by: { activityDate(for: $0) > activityDate(for: $1) })
            .prefix(sessionPreviewLimit)
            .map { snapshot in
                let key = snapshot.sessionKey
                return SessionPreview(
                    provider: snapshot.provider,
                    threadID: snapshot.threadID,
                    title: displayTitle(for: snapshot),
                    statusText: statusText(
                        provider: snapshot.provider,
                        sessionKey: key,
                        event: latestLogEvents[key],
                        recentActivity: activityDate(for: snapshot)
                    ),
                    sourceLabel: snapshot.provider.displayName,
                    userPreview: latestUserPreviews[key]?.text ?? fallbackUserPreview(for: snapshot),
                    assistantPreview: latestAssistantPreviews[key]?.text,
                    latestToolSummary: latestToolSummary(for: latestLogEvents[key]),
                    updatedAt: activityDate(for: snapshot),
                    isPrimary: key == primaryKey,
                    navigationTarget: snapshot.navigationTarget
                )
            }

        let fallbackProvider = activeProvider ?? .codex
        return IslandSnapshot(
            activeProvider: activeProvider,
            primaryThreadID: primary?.threadID,
            threadTitle: primary.map(displayTitle(for:)) ?? "No active AI session",
            statusText: statusText(
                provider: fallbackProvider,
                sessionKey: primaryKey,
                event: event,
                recentActivity: recentActivity
            ),
            latestToolSummary: latestToolSummary(for: event),
            sourceLabel: activeProvider?.displayName ?? "AI Tools",
            activeSessionCount: providerSnapshots.count,
            sessionPreviews: sessionPreviews,
            shouldNotifyCompletion: didConfirmCompletion && shouldNotifyCompletion(for: primaryKey)
        )
    }

    private func snapshots(for provider: ProviderKind) -> [ThreadSnapshot] {
        threadSnapshots.values.filter { $0.provider == provider }
    }

    private func primarySnapshot() -> ThreadSnapshot? {
        threadSnapshots.values.max { lhs, rhs in
            let lhsDescriptor = primarySortDescriptor(for: lhs)
            let rhsDescriptor = primarySortDescriptor(for: rhs)
            if lhsDescriptor.priority == rhsDescriptor.priority {
                return lhsDescriptor.activity < rhsDescriptor.activity
            }
            return lhsDescriptor.priority < rhsDescriptor.priority
        }
    }

    private func primarySortDescriptor(for snapshot: ThreadSnapshot) -> (priority: Int, activity: Date) {
        let key = snapshot.sessionKey
        let activity = activityDate(for: snapshot)
        let priority: Int
        if isCompletionConfirmed(for: key) {
            priority = 1
        } else if let event = latestLogEvents[key] {
            switch event.kind {
            case .toolStarted, .toolUpdated:
                priority = 4
            case .responseCreated, .responseInProgress, .toolCompleted, .responseCompleted:
                priority = 3
            }
        } else if now().timeIntervalSince(activity) < 5 {
            priority = 2
        } else {
            priority = 0
        }
        return (priority, activity)
    }

    private func shouldReplacePreview(current: SessionMessagePreview?, replacement: SessionMessagePreview) -> Bool {
        guard let current else {
            return true
        }
        return replacement.timestamp >= current.timestamp
    }

    private func fallbackUserPreview(for snapshot: ThreadSnapshot) -> String? {
        guard let firstUserMessage = snapshot.firstUserMessage else {
            return nil
        }
        let sanitized = SessionPreviewTextSanitizer.sanitize(firstUserMessage)
        return sanitized.isEmpty ? nil : sanitized
    }

    private func displayTitle(for snapshot: ThreadSnapshot) -> String {
        let sanitized = SessionPreviewTextSanitizer.sanitize(snapshot.title, previewLimit: 90)
        return sanitized.isEmpty ? "Untitled session" : sanitized
    }

    private func statusText(
        provider: ProviderKind,
        sessionKey: String?,
        event: CodexLogEvent?,
        recentActivity: Date?
    ) -> String {
        if let sessionKey, isCompletionConfirmed(for: sessionKey) {
            return "Done"
        }
        guard let event else {
            if let recentActivity, now().timeIntervalSince(recentActivity) < 5 {
                return "Running"
            }
            return "Watching \(provider.displayName)"
        }
        switch event.kind {
        case .responseCreated, .responseInProgress, .toolCompleted:
            return "Running"
        case .toolStarted, .toolUpdated:
            return "Tool active"
        case .responseCompleted:
            return "Running"
        }
    }

    private func latestToolSummary(for event: CodexLogEvent?) -> String? {
        guard let event else {
            return nil
        }
        switch event.kind {
        case .toolStarted, .toolUpdated, .toolCompleted:
            return event.summary
        case .responseCreated, .responseInProgress, .responseCompleted:
            return nil
        }
    }

    private func activityDate(for snapshot: ThreadSnapshot) -> Date {
        let key = snapshot.sessionKey
        let latestEventDate = latestLogEvents[key]?.timestamp ?? snapshot.updatedAt
        let latestActivityDate = latestActivityTimestamps[key] ?? snapshot.updatedAt
        return max(snapshot.updatedAt, max(latestEventDate, latestActivityDate))
    }

    private func isCompletionConfirmed(for sessionKey: String) -> Bool {
        guard completionCandidates[sessionKey] != nil else {
            return false
        }

        return now().timeIntervalSince(lastActivity(for: sessionKey)) >= completionConfirmationDeadline
    }

    private func lastActivity(for sessionKey: String) -> Date {
        max(
            latestActivityTimestamps[sessionKey] ?? .distantPast,
            threadSnapshots[sessionKey]?.updatedAt ?? .distantPast
        )
    }

    private func shouldNotifyCompletion(for sessionKey: String?) -> Bool {
        guard let sessionKey,
              let completionCandidate = completionCandidates[sessionKey],
              isCompletionConfirmed(for: sessionKey) else {
            return false
        }
        return deliveredCompletionCandidates[sessionKey] != completionCandidate
    }

    private var completionConfirmationDeadline: TimeInterval {
        completionIdleThreshold + completionConfirmationThreshold
    }
}
