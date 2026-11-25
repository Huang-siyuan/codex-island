import Foundation

struct DataSourceVersion: Equatable {
    private struct Entry: Equatable {
        let path: String
        let modificationDate: Date?
        let fileSize: UInt64?
    }

    private let entries: [Entry]

    static func capture(files: [URL]) -> DataSourceVersion {
        DataSourceVersion(entries: files
            .map(makeEntry(for:))
            .sorted { $0.path < $1.path })
    }

    private static func makeEntry(for url: URL) -> Entry {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return Entry(path: url.path, modificationDate: nil, fileSize: nil)
        }
        return Entry(
            path: url.path,
            modificationDate: attributes[.modificationDate] as? Date,
            fileSize: (attributes[.size] as? NSNumber)?.uint64Value
        )
    }
}

// Start at visible roots so an archived, internal or missing ancestor hides its entire subtree.
enum CodexThreadHierarchy {
    static func queryPrefix(databaseURL: URL) throws -> String {
        struct Column: Decodable { let name: String }
        let columns: [Column] = try SQLiteShell().query(databaseURL: databaseURL, query: "pragma table_info(threads)")
        let names = Set(columns.map(\.name))
        let parent = names.contains("attached_thread_parent_id") ? "attached_thread_parent_id" : "NULL"
        let kind = names.contains("thread_source") ? "coalesce(thread_source, '')" : "''"
        return """
            with recursive visible as materialized (
                select id, \(parent) as parent_id from threads
                where archived = 0
                  and source in ('vscode', 'cli', 'exec', 'appServer', 'desktop', '{"custom":"atlas"}', '{"custom":"chatgpt"}')
                  and \(kind) not in ('subagent', 'chatgpt_hidden', 'ambient_suggestions')
            ), family(id, root_id) as (
                select id, id from visible where parent_id is null
                union all
                select child.id, family.root_id from visible child join family on child.parent_id = family.id
            )
            """
    }
}

public final class CodexStateStore {
    private let environment: AppEnvironment
    private let shell = SQLiteShell()
    private let sessionIndexReader = SessionIndexReader()

    public init(environment: AppEnvironment = .default) {
        self.environment = environment
    }

    func currentDataVersion(transcriptURLs: [URL] = []) -> DataSourceVersion {
        DataSourceVersion.capture(files: [
            environment.stateStoreURL,
            URL(fileURLWithPath: environment.stateStoreURL.path + "-wal"),
            environment.logsStoreURL,
            URL(fileURLWithPath: environment.logsStoreURL.path + "-wal"),
            environment.sessionIndexURL,
        ] + transcriptURLs)
    }

    public func fetchRecentThreads(limit: Int = 6) throws -> [ThreadSnapshot] {
        try fetchThreadFamily(limit: limit).filter { $0.mainThreadID == nil }
    }

    func fetchThreadFamily(limit: Int) throws -> [ThreadSnapshot] {
        let prefix = try CodexThreadHierarchy.queryPrefix(databaseURL: environment.stateStoreURL)
        let rows: [ThreadRow] = try shell.query(databaseURL: environment.stateStoreURL, query: """
            \(prefix), recent as (
                select root_id from family join threads using (id)
                group by root_id order by max(updated_at) desc, root_id limit \(limit)
            )
            select threads.id, title, source, cwd, updated_at, first_user_message, rollout_path,
                   nullif(family.root_id, threads.id) as main_thread_id
            from threads join family using (id) join recent using (root_id)
            order by updated_at desc, threads.id
            """)
        let titles = try? sessionIndexReader.readTitleOverrides(
            from: environment.sessionIndexURL, threadIDs: Set(rows.map(\.id))
        )
        return rows.map {
            ThreadSnapshot(
                threadID: $0.id,
                title: titles?[$0.id] ?? $0.title,
                source: $0.source,
                cwd: $0.cwd,
                updatedAt: Date(timeIntervalSince1970: TimeInterval($0.updatedAt)),
                firstUserMessage: $0.firstUserMessage,
                rolloutPath: $0.rolloutPath,
                mainThreadID: $0.mainThreadID
            )
        }
    }

    public func fetchLogRows(threadID: String, afterID: Int64, limit: Int = 64) throws -> [LogRow] {
        let escapedThreadID = threadID.replacingOccurrences(of: "'", with: "''")
        let query: String
        if afterID > 0 {
            query = """
            select id, ts, level, target, feedback_log_body as body, thread_id, process_uuid
            from logs
            where thread_id = '\(escapedThreadID)' and id > \(afterID)
            order by id asc
            limit \(limit);
            """
        } else {
            query = """
            select id, ts, level, target, body, thread_id, process_uuid
            from (
                select id, ts, level, target, feedback_log_body as body, thread_id, process_uuid
                from logs
                where thread_id = '\(escapedThreadID)'
                order by id desc
                limit \(limit)
            )
            order by id asc;
            """
        }

        let rows: [LogShellRow] = try shell.query(databaseURL: environment.logsStoreURL, query: query)
        return rows.map {
            LogRow(
                id: $0.id,
                timestamp: $0.ts,
                level: $0.level,
                target: $0.target,
                body: $0.body,
                threadID: $0.threadID,
                processUUID: $0.processUUID
            )
        }
    }

    public func fetchLogRows(afterIDsByThread: [String: Int64], limitPerThread: Int = 64) throws -> [LogRow] {
        guard !afterIDsByThread.isEmpty else {
            return []
        }

        let perThreadQueries = afterIDsByThread.keys.sorted().enumerated().map { index, threadID -> String in
            let afterID = afterIDsByThread[threadID] ?? 0
            let escapedThreadID = threadID.replacingOccurrences(of: "'", with: "''")

            if afterID > 0 {
                return """
                select * from (
                    select id, ts, level, target, feedback_log_body as body, thread_id, process_uuid
                    from logs
                    where thread_id = '\(escapedThreadID)' and id > \(afterID)
                    order by id asc
                    limit \(limitPerThread)
                ) as thread_\(index)
                """
            }

            return """
            select * from (
                select id, ts, level, target, body, thread_id, process_uuid
                from (
                    select id, ts, level, target, feedback_log_body as body, thread_id, process_uuid
                    from logs
                    where thread_id = '\(escapedThreadID)'
                    order by id desc
                    limit \(limitPerThread)
                )
                order by id asc
            ) as thread_\(index)
            """
        }

        let query = perThreadQueries.joined(separator: "\nunion all\n") + "\norder by id asc;"
        let rows: [LogShellRow] = try shell.query(databaseURL: environment.logsStoreURL, query: query)
        return rows.map {
            LogRow(
                id: $0.id,
                timestamp: $0.ts,
                level: $0.level,
                target: $0.target,
                body: $0.body,
                threadID: $0.threadID,
                processUUID: $0.processUUID
            )
        }
    }
}

private struct ThreadRow: Decodable {
    let id: String
    let title: String
    let source: String
    let cwd: String?
    let updatedAt: Int64
    let firstUserMessage: String?
    let rolloutPath: String?
    let mainThreadID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case source
        case cwd
        case updatedAt = "updated_at"
        case firstUserMessage = "first_user_message"
        case mainThreadID = "main_thread_id"
        case rolloutPath = "rollout_path"
    }
}

private struct LogShellRow: Decodable {
    let id: Int64
    let ts: Int64
    let level: String
    let target: String
    let body: String
    let threadID: String?
    let processUUID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ts
        case level
        case target
        case body
        case threadID = "thread_id"
        case processUUID = "process_uuid"
    }
}
