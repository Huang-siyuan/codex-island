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
            self.threadSnapshots[snapshot.threadID] = snapshot
        }
    }

    public func apply(logEvents: [CodexLogEvent]) {
        for event in logEvents {
            latestLogEvents[event.threadID] = event
            latestActivityTimestamps[event.threadID] = max(latestActivityTimestamps[event.threadID] ?? .distantPast, event.timestamp)

            switch event.kind {
            case .responseCompleted:
                if completionCandidates[event.threadID] == nil {
                    completionCandidates[event.threadID] = event.timestamp
                }
            case .responseCreated, .responseInProgress, .toolStarted, .toolUpdated, .toolCompleted:
                if let completionCandidate = completionCandidates[event.threadID], event.timestamp >= completionCandidate {
                    completionCandidates.removeValue(forKey: event.threadID)
                    deliveredCompletionCandidates.removeValue(forKey: event.threadID)
                }
            }
        }
    }

    public func apply(messagePreviews: [SessionMessagePreview]) {
        for preview in messagePreviews {
            switch preview.author {
            case .user:
                if shouldReplacePreview(current: latestUserPreviews[preview.threadID], replacement: preview) {
                    latestUserPreviews[preview.threadID] = preview
                }
            case .assistant:
                if shouldReplacePreview(current: latestAssistantPreviews[preview.threadID], replacement: preview) {
                    latestAssistantPreviews[preview.threadID] = preview
                }
            }
        }
    }

    public func recordActivity(threadID: String, timestamp: Date) {
        latestActivityTimestamps[threadID] = max(latestActivityTimestamps[threadID] ?? .distantPast, timestamp)
    }

    public func consumeCompletionNotification(for threadID: String) {
        guard let completionCandidate = completionCandidates[threadID] else {
            return
        }
        deliveredCompletionCandidates[threadID] = completionCandidate
    }

    public var currentSnapshot: IslandSnapshot {
        let primary = threadSnapshots.values.max(by: { activityDate(for: $0) < activityDate(for: $1) })
        let event = primary.flatMap { latestLogEvents[$0.threadID] }
        let recentActivity = primary.map(activityDate(for:))
        let didConfirmCompletion = primary.map { isCompletionConfirmed(for: $0.threadID) } ?? false
        let sessionPreviews = threadSnapshots.values
            .sorted(by: { activityDate(for: $0) > activityDate(for: $1) })
            .prefix(sessionPreviewLimit)
            .map { snapshot in
                let threadID = snapshot.threadID
                let status = statusText(
                    for: threadID,
                    event: latestLogEvents[threadID],
                    recentActivity: activityDate(for: snapshot)
                )

                return SessionPreview(
                    threadID: threadID,
                    title: displayTitle(for: snapshot),
                    statusText: status,
                    sourceLabel: sourceLabel(for: snapshot.source),
                    userPreview: latestUserPreviews[threadID]?.text ?? fallbackUserPreview(for: snapshot),
                    assistantPreview: latestAssistantPreviews[threadID]?.text,
                    latestToolSummary: latestToolSummary(for: latestLogEvents[threadID]),
                    updatedAt: activityDate(for: snapshot),
                    isPrimary: threadID == primary?.threadID
                )
            }

        return IslandSnapshot(
            primaryThreadID: primary?.threadID,
            threadTitle: primary.map(displayTitle(for:)) ?? "No active Codex thread",
            statusText: statusText(for: primary?.threadID, event: event, recentActivity: recentActivity),
            latestToolSummary: latestToolSummary(for: event),
            sourceLabel: sourceLabel(for: primary?.source),
            activeSessionCount: threadSnapshots.count,
            sessionPreviews: sessionPreviews,
            shouldNotifyCompletion: didConfirmCompletion && shouldNotifyCompletion(for: primary?.threadID)
        )
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

    private func statusText(for threadID: String?, event: CodexLogEvent?, recentActivity: Date?) -> String {
        if let threadID, isCompletionConfirmed(for: threadID) {
            return "Done"
        }
        guard let event else {
            if let recentActivity, now().timeIntervalSince(recentActivity) < 5 {
                return "Running"
            }
            return "Watching Codex"
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

    private func sourceLabel(for source: String?) -> String {
        guard let source, !source.isEmpty else {
            return "Codex"
        }
        return source.capitalized
    }

    private func activityDate(for snapshot: ThreadSnapshot) -> Date {
        let latestEventDate = latestLogEvents[snapshot.threadID]?.timestamp ?? snapshot.updatedAt
        let latestActivityDate = latestActivityTimestamps[snapshot.threadID] ?? snapshot.updatedAt
        return max(snapshot.updatedAt, max(latestEventDate, latestActivityDate))
    }

    private func isCompletionConfirmed(for threadID: String) -> Bool {
        guard completionCandidates[threadID] != nil else {
            return false
        }

        return now().timeIntervalSince(lastActivity(for: threadID)) >= completionConfirmationDeadline
    }

    private func lastActivity(for threadID: String) -> Date {
        max(
            latestActivityTimestamps[threadID] ?? .distantPast,
            threadSnapshots[threadID]?.updatedAt ?? .distantPast
        )
    }

    private func shouldNotifyCompletion(for threadID: String?) -> Bool {
        guard let threadID,
              let completionCandidate = completionCandidates[threadID],
              isCompletionConfirmed(for: threadID) else {
            return false
        }
        return deliveredCompletionCandidates[threadID] != completionCandidate
    }

    private var completionConfirmationDeadline: TimeInterval {
        completionIdleThreshold + completionConfirmationThreshold
    }
}
