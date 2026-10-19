import Foundation
import SQLite3
import Testing
@testable import CodexIslandCore

@Test
func codexCompletionUsesTranscriptWithEmptyLogsAndNotifiesOnce() throws {
    let fixture = try CompletionFixture()
    defer { fixture.remove() }
    try fixture.append(lifecycleLine("task_started", second: 1))
    let provider = fixture.provider()
    let coordinator = SessionCoordinator(now: { fixture.start.addingTimeInterval(30) })
    let initial = try provider.poll()
    coordinator.apply(threadSnapshots: initial.threadSnapshots)
    coordinator.apply(logEvents: initial.logEvents)
    #expect(coordinator.pendingCompletion == nil)

    // Only the JSONL file changes: state/log database versions remain unchanged.
    try fixture.append(lifecycleLine("task_complete", second: 10))
    let completed = try provider.poll()
    coordinator.apply(logEvents: completed.logEvents)
    #expect(completed.logEvents.map(\.kind) == [.responseCompleted])
    #expect(coordinator.pendingCompletion?.threadID == "thread-1")
    coordinator.consumeCompletionNotification(for: "thread-1")
    coordinator.apply(logEvents: try provider.poll().logEvents)
    #expect(coordinator.pendingCompletion == nil)

    try fixture.append(lifecycleLine("token_count", second: 11))
    #expect(try provider.poll().logEvents.isEmpty)

    try fixture.append(lifecycleLine("task_started", second: 20))
    coordinator.apply(logEvents: try provider.poll().logEvents)
    try fixture.append(lifecycleLine("task_complete", second: 21))
    coordinator.apply(logEvents: try provider.poll().logEvents)
    #expect(coordinator.pendingCompletion?.threadID == "thread-1")
    coordinator.consumeCompletionNotification(for: "thread-1")
    try fixture.append(lifecycleLine("task_started", second: 22) + lifecycleLine("task_complete", second: 23))
    coordinator.apply(logEvents: try provider.poll().logEvents)
    #expect(coordinator.pendingCompletion?.threadID == "thread-1")
}

@Test
func codexCompletionDoesNotReplayTasksFinishedBeforeLaunch() throws {
    let fixture = try CompletionFixture()
    defer { fixture.remove() }
    try fixture.append(lifecycleLine("task_complete", second: 1))
    let provider = fixture.provider(startedAt: fixture.start.addingTimeInterval(2))
    #expect(try provider.poll().logEvents.isEmpty)
    try fixture.append(lifecycleLine("token_count", second: 3))
    #expect(try provider.poll().logEvents.isEmpty)
}

@Test
func codexCompletionWaitsForWholeRecordAndHandlesInterruptAndNewTurn() throws {
    let fixture = try CompletionFixture()
    defer { fixture.remove() }
    try fixture.append(lifecycleLine("task_started", second: 1))
    let provider = fixture.provider()
    _ = try provider.poll()
    let completion = lifecycleLine("task_complete", second: 2)
    let midpoint = completion.index(completion.startIndex, offsetBy: completion.count / 2)
    try fixture.append(String(completion[..<midpoint]))
    #expect(try provider.poll().logEvents.isEmpty)
    try fixture.append(String(completion[midpoint...]))
    #expect(try provider.poll().logEvents.map(\.kind) == [.responseCompleted])
    try fixture.append(lifecycleLine("task_started", second: 3) + lifecycleLine("turn_aborted", second: 4))
    #expect(try provider.poll().logEvents.map(\.kind) == [.responseInterrupted])
    try fixture.append(lifecycleLine("task_complete", second: 5) + lifecycleLine("task_started", second: 6))
    #expect(try provider.poll().logEvents.map(\.kind) == [.responseCreated])
}

@Test
func codexCompletionUsesTaskLifecycleInsteadOfIntermediateModelCompletion() throws {
    let fixture = try CompletionFixture()
    defer { fixture.remove() }
    try fixture.append(lifecycleLine("task_started", second: 1))
    try fixture.execute(
        "insert into logs values (1, \(Int(fixture.start.timeIntervalSince1970) + 2), 'INFO', 'test', 'response.completed', 'thread-1', null)",
        at: fixture.logs
    )
    let provider = fixture.provider()
    #expect(try provider.poll().logEvents.map(\.kind) == [.responseCreated])
    try fixture.append(lifecycleLine("task_complete", second: 3))
    #expect(try provider.poll().logEvents.map(\.kind) == [.responseCompleted])
}

@Test
func codexCompletionStillWorksWhenDiagnosticLogsCannotBeRead() throws {
    let fixture = try CompletionFixture()
    defer { fixture.remove() }
    try fixture.execute("drop table logs", at: fixture.logs)
    try fixture.append(lifecycleLine("task_complete", second: 1))
    #expect(try fixture.provider().poll().logEvents.map(\.kind) == [.responseCompleted])
}

@Test
func codexCompletionRetainsLogFallbackWithoutTranscript() throws {
    let fixture = try CompletionFixture()
    defer { fixture.remove() }
    try fixture.execute(
        "insert into logs values (1, \(Int(fixture.start.timeIntervalSince1970) + 2), 'INFO', 'test', 'response.completed', 'thread-1', null)",
        at: fixture.logs
    )
    #expect(try fixture.provider().poll().logEvents.map(\.kind) == [.responseCompleted])
}

@Test
func codexTranscriptReaderHandlesLargeRecordsTruncationAndReplacement() throws {
    let fixture = try CompletionFixture()
    defer { fixture.remove() }
    let reader = CodexTranscriptEventReader()
    let largeRecord = "{\"type\":\"response_item\",\"payload\":{\"text\":\"" + String(repeating: "x", count: 150_000) + "\"}}\n"
    try fixture.append(lifecycleLine("task_started", second: 1) + largeRecord)
    #expect(try reader.latestEvent(at: fixture.transcript, threadID: "thread-1")?.kind == .responseCreated)
    try fixture.append(largeRecord + lifecycleLine("task_complete", second: 2))
    #expect(try reader.latestEvent(at: fixture.transcript, threadID: "thread-1")?.kind == .responseCompleted)
    // Truncation retains the inode; atomic replacement changes it.
    try lifecycleLine("turn_aborted", second: 3).write(to: fixture.transcript, atomically: false, encoding: .utf8)
    #expect(try reader.latestEvent(at: fixture.transcript, threadID: "thread-1")?.kind == .responseInterrupted)
    try lifecycleLine("task_started", second: 4).write(to: fixture.transcript, atomically: true, encoding: .utf8)
    #expect(try reader.latestEvent(at: fixture.transcript, threadID: "thread-1")?.kind == .responseCreated)
}

@Test
func codexCompletionTracksTheFourthRecentSession() throws {
    let fixture = try CompletionFixture()
    defer { fixture.remove() }
    for index in 2...4 {
        try fixture.execute("insert into threads values ('thread-\(index)', 'Other', 'desktop', null, \(Int(fixture.start.timeIntervalSince1970) + index), null, null, 0)", at: fixture.state)
    }
    try fixture.append(lifecycleLine("task_complete", second: 1))
    #expect(try fixture.provider().poll().logEvents.first?.threadID == "thread-1")
}

@Test
func pollingEngineDeliversCompletionWhileAnotherSessionIsRunning() async {
    let now = Date()
    let coordinator = SessionCoordinator(now: { now })
    let completed = ThreadSnapshot(threadID: "done", title: "Finished", source: "desktop", cwd: nil, updatedAt: now.addingTimeInterval(-10))
    let running = ThreadSnapshot(threadID: "running", title: "Active", source: "desktop", cwd: nil, updatedAt: now)
    coordinator.apply(threadSnapshots: [completed, running])
    coordinator.apply(logEvents: [
        CodexLogEvent(threadID: "done", kind: .responseCompleted, toolName: nil, summary: "Completed", timestamp: now.addingTimeInterval(-10)),
        CodexLogEvent(threadID: "running", kind: .responseCreated, toolName: nil, summary: "Started", timestamp: now),
    ])
    let engine = PollingEngine(coordinator: coordinator, providers: [])
    let result = await engine.pollOnce()
    #expect(result.snapshot.primaryThreadID == "running")
    #expect(result.completionNotification?.threadID == "done")
    await engine.consumeCompletionNotification(for: "done")
    #expect(await engine.pollOnce().completionNotification == nil)
}

private func lifecycleLine(_ type: String, second: Int) -> String {
    let seconds = String(format: "%02d", second)
    return "{\"timestamp\":\"2026-10-19T12:00:\(seconds).123Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"\(type)\"}}\n"
}

private struct CompletionFixture {
    let root: URL
    let state: URL
    let logs: URL
    let transcript: URL
    let start = ISO8601DateFormatter().date(from: "2026-10-19T12:00:00Z")!

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        state = root.appendingPathComponent("state.sqlite")
        logs = root.appendingPathComponent("logs.sqlite")
        transcript = root.appendingPathComponent("rollout.jsonl")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try execute("create table threads (id text, title text, source text, cwd text, updated_at integer, first_user_message text, rollout_path text, archived integer)", at: state)
        let path = transcript.path.replacingOccurrences(of: "'", with: "''")
        try execute("insert into threads values ('thread-1', 'Test task', 'desktop', null, \(Int(start.timeIntervalSince1970)), null, '\(path)', 0)", at: state)
        try execute("create table logs (id integer, ts integer, level text, target text, feedback_log_body text, thread_id text, process_uuid text)", at: logs)
    }

    func provider(startedAt: Date? = nil) -> CodexSessionProvider {
        let environment = AppEnvironment(
            codexHome: root, sessionIndexURL: root.appendingPathComponent("index.jsonl"),
            stateStoreURL: state, logsStoreURL: logs,
            claudeHome: root, claudeProjectsDirectory: root.appendingPathComponent("claude"),
            codeBuddySupportDirectory: root, codeBuddySessionsStoreURL: root.appendingPathComponent("buddy.sqlite"),
            codeBuddyTodosDirectory: root, codeBuddyGenieHistoryDirectory: root, codeBuddyCLIURL: root
        )
        return CodexSessionProvider(store: CodexStateStore(environment: environment), monitoringStartedAt: startedAt ?? start)
    }

    func append(_ text: String) throws {
        if !FileManager.default.fileExists(atPath: transcript.path) {
            FileManager.default.createFile(atPath: transcript.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: transcript)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }

    func execute(_ sql: String, at url: URL) throws {
        var database: OpaquePointer?
        #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        let connection = try #require(database)
        #expect(sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
