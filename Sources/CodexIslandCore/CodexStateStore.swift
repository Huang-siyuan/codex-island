import Foundation

public enum SQLiteShellError: Error, LocalizedError {
    case commandFailed(String)
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let message), .invalidJSON(let message):
            return message
        }
    }
}

public final class CodexStateStore {
    private let environment: AppEnvironment
    private let shell = SQLiteShell()
    private let sessionIndexReader = SessionIndexReader()

    public init(environment: AppEnvironment = .default) {
        self.environment = environment
    }

    public func fetchRecentThreads(limit: Int = 6) throws -> [ThreadSnapshot] {
        let query = """
        select id, title, source, cwd, updated_at, first_user_message
        from threads
        where archived = 0
        order by updated_at desc
        limit \(limit);
        """

        do {
            let rows: [ThreadRow] = try shell.query(databaseURL: environment.stateStoreURL, query: query)
            if rows.isEmpty {
                return try sessionIndexReader.readRecentSnapshots(from: environment.sessionIndexURL, limit: limit)
            }
            let titleOverrides = try? sessionIndexReader.readTitleOverrides(
                from: environment.sessionIndexURL,
                threadIDs: Set(rows.map(\.id))
            )
            return rows.map {
                ThreadSnapshot(
                    threadID: $0.id,
                    title: titleOverrides?[$0.id] ?? $0.title,
                    source: $0.source,
                    cwd: $0.cwd,
                    updatedAt: Date(timeIntervalSince1970: TimeInterval($0.updatedAt)),
                    firstUserMessage: $0.firstUserMessage
                )
            }
        } catch {
            return try sessionIndexReader.readRecentSnapshots(from: environment.sessionIndexURL, limit: limit)
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

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case source
        case cwd
        case updatedAt = "updated_at"
        case firstUserMessage = "first_user_message"
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

private struct SQLiteShell {
    func query<T: Decodable>(databaseURL: URL, query: String) throws -> [T] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return []
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-json", databaseURL.path, query]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        // Drain stdout before waiting so large sqlite result sets cannot fill the pipe
        // and deadlock the child process.
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let message = String(decoding: err, as: UTF8.self)
            throw SQLiteShellError.commandFailed(message)
        }

        let trimmed = String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw SQLiteShellError.invalidJSON("Could not encode sqlite output")
        }
        return try JSONDecoder().decode([T].self, from: data)
    }
}
