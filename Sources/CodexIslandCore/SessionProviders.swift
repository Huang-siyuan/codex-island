import Foundation

public struct ProviderSessionMaterial: Sendable, Equatable {
    public let threadSnapshot: ThreadSnapshot
    public let userPreview: SessionMessagePreview?
    public let assistantPreview: SessionMessagePreview?
    public let event: CodexLogEvent?

    public init(
        threadSnapshot: ThreadSnapshot,
        userPreview: SessionMessagePreview?,
        assistantPreview: SessionMessagePreview?,
        event: CodexLogEvent?
    ) {
        self.threadSnapshot = threadSnapshot
        self.userPreview = userPreview
        self.assistantPreview = assistantPreview
        self.event = event
    }
}

public struct ProviderPollResult: Sendable, Equatable {
    public let provider: ProviderKind
    public let threadSnapshots: [ThreadSnapshot]
    public let logEvents: [CodexLogEvent]
    public let messagePreviews: [SessionMessagePreview]

    public init(
        provider: ProviderKind,
        threadSnapshots: [ThreadSnapshot],
        logEvents: [CodexLogEvent],
        messagePreviews: [SessionMessagePreview]
    ) {
        self.provider = provider
        self.threadSnapshots = threadSnapshots
        self.logEvents = logEvents
        self.messagePreviews = messagePreviews
    }
}

public protocol SessionProvider: AnyObject {
    var kind: ProviderKind { get }
    func poll() throws -> ProviderPollResult
}

public final class CodexSessionProvider: SessionProvider {
    public let kind: ProviderKind = .codex

    private let trackedThreadLimit: Int
    private let parser: LogsEventParser
    private let previewParser: SessionPreviewParser
    private let store: CodexStateStore
    private var lastSeenLogIDByThread: [String: Int64]

    public init(
        trackedThreadLimit: Int = 3,
        parser: LogsEventParser = LogsEventParser(),
        previewParser: SessionPreviewParser = SessionPreviewParser(),
        store: CodexStateStore = CodexStateStore(),
        lastSeenLogIDByThread: [String: Int64] = [:]
    ) {
        self.trackedThreadLimit = trackedThreadLimit
        self.parser = parser
        self.previewParser = previewParser
        self.store = store
        self.lastSeenLogIDByThread = lastSeenLogIDByThread
    }

    public func poll() throws -> ProviderPollResult {
        let threads = try store.fetchRecentThreads()
        let trackedThreads = Array(threads.prefix(trackedThreadLimit))
        let afterIDsByThread = trackedThreads.reduce(into: [String: Int64]()) { partialResult, thread in
            partialResult[thread.threadID] = lastSeenLogIDByThread[thread.threadID] ?? 0
        }
        let fetchedRows = try store.fetchLogRows(afterIDsByThread: afterIDsByThread)
        let rowsByThread = Dictionary(grouping: fetchedRows, by: { $0.threadID ?? "" })

        var logEvents: [CodexLogEvent] = []
        var previews: [SessionMessagePreview] = []

        for thread in trackedThreads {
            let rows = rowsByThread[thread.threadID] ?? []
            if let newestRow = rows.last {
                lastSeenLogIDByThread[thread.threadID] = newestRow.id
            }
            previews.append(contentsOf: rows.compactMap(previewParser.parse(row:)))
            logEvents.append(contentsOf: rows.compactMap(parser.parse(row:)))
        }

        return ProviderPollResult(
            provider: kind,
            threadSnapshots: threads,
            logEvents: logEvents,
            messagePreviews: previews
        )
    }
}

public final class ClaudeCodeSessionProvider: SessionProvider {
    public let kind: ProviderKind = .claudeCode

    private let environment: AppEnvironment
    private let parser: ClaudeTranscriptParser
    private let sessionLimit: Int

    public init(
        environment: AppEnvironment = .default,
        parser: ClaudeTranscriptParser = ClaudeTranscriptParser(),
        sessionLimit: Int = 6
    ) {
        self.environment = environment
        self.parser = parser
        self.sessionLimit = sessionLimit
    }

    public func poll() throws -> ProviderPollResult {
        guard FileManager.default.fileExists(atPath: environment.claudeProjectsDirectory.path) else {
            return ProviderPollResult(provider: kind, threadSnapshots: [], logEvents: [], messagePreviews: [])
        }

        let files = try recentTranscriptFiles(limit: sessionLimit)
        let materials = try files.compactMap { fileURL -> ProviderSessionMaterial? in
            let transcript = try String(contentsOf: fileURL, encoding: .utf8)
            let updatedAt = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? Date()
            let sessionID = fileURL.deletingPathExtension().lastPathComponent
            return parser.parse(
                sessionID: sessionID,
                transcript: transcript,
                updatedAt: updatedAt,
                workingDirectory: nil
            )
        }

        return ProviderPollResult(
            provider: kind,
            threadSnapshots: materials.map(\.threadSnapshot),
            logEvents: materials.compactMap(\.event),
            messagePreviews: materials.flatMap { material in
                [material.userPreview, material.assistantPreview].compactMap { $0 }
            }
        )
    }

    private func recentTranscriptFiles(limit: Int) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: environment.claudeProjectsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let files = enumerator.compactMap { element -> URL? in
            guard let url = element as? URL,
                  url.pathExtension == "jsonl",
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return nil
            }
            return url
        }

        return files
            .sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhs > rhs
            }
            .prefix(limit)
            .map { $0 }
    }
}

public struct CodeBuddySessionRecord: Sendable, Equatable {
    public let conversationID: String
    public let cwd: String?
    public let title: String
    public let status: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        conversationID: String,
        cwd: String?,
        title: String,
        status: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.conversationID = conversationID
        self.cwd = cwd
        self.title = title
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct CodeBuddyTodo: Sendable, Equatable {
    public let id: String
    public let status: String
    public let content: String

    public init(id: String, status: String, content: String) {
        self.id = id
        self.status = status
        self.content = content
    }
}

public struct CodeBuddyTodos: Sendable, Equatable {
    public let conversationID: String
    public let items: [CodeBuddyTodo]
    public let updatedAt: Date

    public init(conversationID: String, items: [CodeBuddyTodo], updatedAt: Date) {
        self.conversationID = conversationID
        self.items = items
        self.updatedAt = updatedAt
    }
}

public struct CodeBuddySessionBuilder {
    public init() {}

    public func build(
        session: CodeBuddySessionRecord,
        todos: CodeBuddyTodos?,
        historyUpdatedAt: Date?
    ) -> ProviderSessionMaterial? {
        let inProgressTodo = todos?.items.first(where: { normalizedTodoStatus($0.status) == "in_progress" })
        let completedTodos = todos?.items.filter { normalizedTodoStatus($0.status) == "completed" } ?? []
        let assistantText: String?
        let eventKind: CodexLogEventKind?

        if let inProgressTodo {
            assistantText = "Working on: \(SessionPreviewTextSanitizer.sanitize(inProgressTodo.content, previewLimit: 120))"
            eventKind = .toolUpdated
        } else if normalizedSessionStatus(session.status) == "completed" {
            assistantText = completedTodos.isEmpty ? "Completed" : "Completed \(completedTodos.count) tasks"
            eventKind = .responseCompleted
        } else if let todos, !todos.items.isEmpty {
            assistantText = "Tracking \(todos.items.count) tasks"
            eventKind = .responseInProgress
        } else if normalizedSessionStatus(session.status) == "running" {
            assistantText = "Working"
            eventKind = .responseInProgress
        } else {
            assistantText = nil
            eventKind = nil
        }

        let updatedAt = [session.updatedAt, todos?.updatedAt, historyUpdatedAt]
            .compactMap { $0 }
            .max() ?? session.updatedAt
        let title = SessionPreviewTextSanitizer.sanitize(session.title, previewLimit: 90)
        let assistantPreview = assistantText.map {
            SessionMessagePreview(
                provider: .codeBuddy,
                threadID: session.conversationID,
                author: .assistant,
                text: $0,
                timestamp: updatedAt
            )
        }
        let event = assistantText.flatMap { summary in
            eventKind.map {
                CodexLogEvent(
                    provider: .codeBuddy,
                    threadID: session.conversationID,
                    kind: $0,
                    toolName: $0 == .toolUpdated ? "todo" : nil,
                    summary: summary,
                    timestamp: updatedAt
                )
            }
        }

        let snapshot = ThreadSnapshot(
            provider: .codeBuddy,
            threadID: session.conversationID,
            title: title.isEmpty ? "Untitled CodeBuddy session" : title,
            source: "codebuddy",
            cwd: session.cwd,
            updatedAt: updatedAt,
            firstUserMessage: nil
        )

        return ProviderSessionMaterial(
            threadSnapshot: snapshot,
            userPreview: nil,
            assistantPreview: assistantPreview,
            event: event
        )
    }

    private func normalizedSessionStatus(_ status: String) -> String {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizedTodoStatus(_ status: String) -> String {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public final class CodeBuddySessionProvider: SessionProvider {
    public let kind: ProviderKind = .codeBuddy

    private let store: CodeBuddyStateStore
    private let builder: CodeBuddySessionBuilder
    private let sessionLimit: Int

    public init(
        store: CodeBuddyStateStore = CodeBuddyStateStore(),
        builder: CodeBuddySessionBuilder = CodeBuddySessionBuilder(),
        sessionLimit: Int = 6
    ) {
        self.store = store
        self.builder = builder
        self.sessionLimit = sessionLimit
    }

    public func poll() throws -> ProviderPollResult {
        let sessions = try store.fetchRecentSessions(limit: sessionLimit)
        guard !sessions.isEmpty else {
            return ProviderPollResult(provider: kind, threadSnapshots: [], logEvents: [], messagePreviews: [])
        }

        let conversationIDs = Set(sessions.map(\.conversationID))
        let todosByConversation = try store.fetchTodos(conversationIDs: conversationIDs)
        let historyByConversation = try store.fetchHistory(conversationIDs: conversationIDs)
        let materials = sessions.compactMap { session in
            builder.build(
                session: session,
                todos: todosByConversation[session.conversationID],
                historyUpdatedAt: historyByConversation[session.conversationID]
            )
        }

        return ProviderPollResult(
            provider: kind,
            threadSnapshots: materials.map(\.threadSnapshot),
            logEvents: materials.compactMap(\.event),
            messagePreviews: materials.flatMap { material in
                [material.userPreview, material.assistantPreview].compactMap { $0 }
            }
        )
    }
}

public final class CodeBuddyStateStore {
    private let environment: AppEnvironment
    private let shell = SQLiteShell()

    public init(environment: AppEnvironment = .default) {
        self.environment = environment
    }

    public func fetchRecentSessions(limit: Int = 6) throws -> [CodeBuddySessionRecord] {
        let query = """
        select key, value
        from ItemTable
        where key like 'session:%';
        """

        let rows: [CodeBuddySessionRow] = try shell.query(databaseURL: environment.codeBuddySessionsStoreURL, query: query)
        let records = rows.compactMap { row in
            decodeSessionRecord(row.value)
        }
        return records
            .sorted(by: { $0.updatedAt > $1.updatedAt })
            .prefix(limit)
            .map { $0 }
    }

    public func fetchTodos(conversationIDs: Set<String>) throws -> [String: CodeBuddyTodos] {
        guard !conversationIDs.isEmpty else {
            return [:]
        }

        return try conversationIDs.reduce(into: [String: CodeBuddyTodos]()) { partialResult, conversationID in
            let fileURL = environment.codeBuddyTodosDirectory.appendingPathComponent("\(conversationID).json")
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return
            }
            let data = try Data(contentsOf: fileURL)
            let payload = try JSONDecoder().decode(CodeBuddyTodosPayload.self, from: data)
            partialResult[conversationID] = CodeBuddyTodos(
                conversationID: payload.conversationID,
                items: payload.todos.map { CodeBuddyTodo(id: $0.id, status: $0.status, content: $0.content) },
                updatedAt: Date(timeIntervalSince1970: TimeInterval(payload.updatedAt) / 1000)
            )
        }
    }

    public func fetchHistory(conversationIDs: Set<String>) throws -> [String: Date] {
        guard !conversationIDs.isEmpty,
              FileManager.default.fileExists(atPath: environment.codeBuddyGenieHistoryDirectory.path) else {
            return [:]
        }

        guard let enumerator = FileManager.default.enumerator(
            at: environment.codeBuddyGenieHistoryDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        return try enumerator.reduce(into: [String: Date]()) { partialResult, element in
            guard let fileURL = element as? URL,
                  fileURL.lastPathComponent == "current.json",
                  (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return
            }

            let data = try Data(contentsOf: fileURL)
            let payload = try JSONDecoder().decode(CodeBuddyHistoryPayload.self, from: data)
            guard conversationIDs.contains(payload.conversationID),
                  let updatedAt = ISO8601DateFormatter().date(from: payload.lastUpdated) else {
                return
            }
            partialResult[payload.conversationID] = max(partialResult[payload.conversationID] ?? .distantPast, updatedAt)
        }
    }

    private func decodeSessionRecord(_ rawValue: String) -> CodeBuddySessionRecord? {
        guard let data = rawValue.data(using: .utf8),
              let payload = try? JSONDecoder().decode(CodeBuddySessionPayload.self, from: data) else {
            return nil
        }
        let title = SessionPreviewTextSanitizer.sanitize(payload.title, previewLimit: 90)
        return CodeBuddySessionRecord(
            conversationID: payload.conversationID,
            cwd: payload.cwd,
            title: title.isEmpty ? "Untitled CodeBuddy session" : title,
            status: payload.status,
            createdAt: Date(timeIntervalSince1970: TimeInterval(payload.createdAt) / 1000),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(payload.updatedAt) / 1000)
        )
    }
}

private struct CodeBuddySessionRow: Decodable {
    let key: String
    let value: String
}

private struct CodeBuddySessionPayload: Decodable {
    let conversationID: String
    let cwd: String?
    let title: String
    let status: String
    let createdAt: Int64
    let updatedAt: Int64
}

private struct CodeBuddyTodosPayload: Decodable {
    let conversationID: String
    let todos: [CodeBuddyTodoPayload]
    let updatedAt: Int64
}

private struct CodeBuddyTodoPayload: Decodable {
    let id: String
    let status: String
    let content: String
}

private struct CodeBuddyHistoryPayload: Decodable {
    let conversationID: String
    let lastUpdated: String
}
