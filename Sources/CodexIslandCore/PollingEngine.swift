import Foundation

public struct CompletionNotificationRequest: Sendable, Equatable {
    public let threadID: String
    public let threadTitle: String

    public init(threadID: String, threadTitle: String) {
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
    private let trackedThreadLimit = 3
    private let parser: LogsEventParser
    private let previewParser: SessionPreviewParser
    private let coordinator: SessionCoordinator
    private let store: CodexStateStore
    private var lastSeenLogIDByThread: [String: Int64]

    public init(
        parser: LogsEventParser = LogsEventParser(),
        previewParser: SessionPreviewParser = SessionPreviewParser(),
        coordinator: SessionCoordinator = SessionCoordinator(),
        store: CodexStateStore = CodexStateStore(),
        lastSeenLogIDByThread: [String: Int64] = [:]
    ) {
        self.parser = parser
        self.previewParser = previewParser
        self.coordinator = coordinator
        self.store = store
        self.lastSeenLogIDByThread = lastSeenLogIDByThread
    }

    public func pollOnce() -> PollingResult {
        do {
            let threads = try store.fetchRecentThreads()
            coordinator.apply(threadSnapshots: threads)

            let trackedThreads = Array(threads.prefix(trackedThreadLimit))
            let afterIDsByThread = trackedThreads.reduce(into: [String: Int64]()) { partialResult, thread in
                partialResult[thread.threadID] = lastSeenLogIDByThread[thread.threadID] ?? 0
            }
            let fetchedRows = try store.fetchLogRows(afterIDsByThread: afterIDsByThread)
            let rowsByThread = Dictionary(grouping: fetchedRows, by: { $0.threadID ?? "" })

            for thread in trackedThreads {
                let rows = rowsByThread[thread.threadID] ?? []
                if let newestRow = rows.last {
                    lastSeenLogIDByThread[thread.threadID] = newestRow.id
                    coordinator.recordActivity(
                        threadID: thread.threadID,
                        timestamp: Date(timeIntervalSince1970: TimeInterval(newestRow.timestamp))
                    )
                }
                coordinator.apply(messagePreviews: rows.compactMap(previewParser.parse(row:)))
                coordinator.apply(logEvents: rows.compactMap(parser.parse(row:)))
            }

            let snapshot = coordinator.currentSnapshot
            let completionNotification = snapshot.shouldNotifyCompletion
                ? snapshot.primaryThreadID.map {
                    CompletionNotificationRequest(threadID: $0, threadTitle: snapshot.threadTitle)
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

    public func consumeCompletionNotification(for threadID: String) {
        coordinator.consumeCompletionNotification(for: threadID)
    }

    private func fallbackSnapshot(errorDescription: String) -> IslandSnapshot {
        IslandSnapshot(
            primaryThreadID: nil,
            threadTitle: "Codex Island",
            statusText: "Waiting for Codex",
            latestToolSummary: errorDescription,
            sourceLabel: "Codex",
            activeSessionCount: 0,
            sessionPreviews: [],
            shouldNotifyCompletion: false
        )
    }
}
