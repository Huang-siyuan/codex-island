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
    #expect(completed.logEvents.map(\.kind) == [.taskCompleted])
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
    #expect(try provider.poll().logEvents.map(\.kind) == [.taskCompleted])
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
    #expect(try provider.poll().logEvents.map(\.kind) == [.taskCompleted])
}

@Test
func codexCompletionStillWorksWhenDiagnosticLogsCannotBeRead() throws {
    let fixture = try CompletionFixture()
    defer { fixture.remove() }
    try fixture.execute("drop table logs", at: fixture.logs)
    try fixture.append(lifecycleLine("task_complete", second: 1))
    #expect(try fixture.provider().poll().logEvents.map(\.kind) == [.taskCompleted])
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
    #expect(try reader.latestEvent(at: fixture.transcript, threadID: "thread-1")?.kind == .taskCompleted)
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

private func inputRecord(type: String, second: Int, callID: String, name: String? = nil, output: String? = nil) throws -> String {
    struct Record: Encodable {
        struct Payload: Encodable {
            let type: String
            let call_id: String
            let name: String?
            let output: String?
        }
        let timestamp: String
        let type = "response_item"
        let payload: Payload
    }
    let record = Record(
        timestamp: String(format: "2026-10-19T12:00:%02d.123Z", second),
        payload: .init(type: type, call_id: callID, name: name, output: output)
    )
    return String(decoding: try JSONEncoder().encode(record), as: UTF8.self) + "\n"
}

@Test(arguments: ["request_user_input", "functions.request_user_input"])
func codexInputRequestTracksSynchronousReply(name: String) throws {
    let fixture = try CompletionFixture()
    defer { fixture.remove() }
    let provider = fixture.provider()
    try fixture.append(lifecycleLine("task_started", second: 1))
    _ = try provider.poll()
    try fixture.append(inputRecord(type: "function_call", second: 2, callID: "input", name: name))
    #expect(try provider.poll().logEvents.map(\.kind) == [.userInputRequested])
    #expect(try provider.poll().logEvents.isEmpty)
    try fixture.append(inputRecord(type: "function_call_output", second: 3, callID: "other", output: "done"))
    #expect(try provider.poll().logEvents.isEmpty)
    try fixture.append(inputRecord(type: "function_call_output", second: 4, callID: "input", output: "user answer"))
    #expect(try provider.poll().logEvents.map(\.kind) == [.responseInProgress])
    // Reconstructing a cached file must not resurrect a question already answered.
    #expect(try fixture.provider().poll().logEvents.map(\.kind) == [.responseInProgress])
}

@Test(arguments: ["request_user_input_async", "functions.request_user_input_async"])
func codexAsyncInputAcknowledgementDoesNotResolveQuestion(name: String) throws {
    let fixture = try CompletionFixture()
    defer { fixture.remove() }
    try fixture.append(lifecycleLine("task_started", second: 1))
    try fixture.append(inputRecord(type: "function_call", second: 2, callID: "input", name: name))
    try fixture.append(inputRecord(type: "function_call_output", second: 3, callID: "input", output: "{\"accepted\":true}"))
    let provider = fixture.provider()
    #expect(try provider.poll().logEvents.map(\.kind) == [.userInputRequested])
    try fixture.append(inputRecord(type: "function_call_output", second: 4, callID: "background", output: "done"))
    #expect(try provider.poll().logEvents.isEmpty)
    try fixture.append(lifecycleLine("user_message", second: 5))
    #expect(try provider.poll().logEvents.map(\.kind) == [.responseInProgress])
    #expect(try fixture.provider().poll().logEvents.map(\.kind) == [.responseInProgress])
}

@Test
func codexInputDoesNotNotifyHistoricalOrAlreadyAnsweredRequests() throws {
    let fixture = try CompletionFixture()
    defer { fixture.remove() }
    try fixture.append(lifecycleLine("task_started", second: 1))
    try fixture.append(inputRecord(type: "function_call", second: 2, callID: "input", name: "request_user_input"))
    let provider = fixture.provider(startedAt: fixture.start.addingTimeInterval(3))
    #expect(try provider.poll().logEvents.isEmpty)
    try fixture.append(inputRecord(type: "function_call_output", second: 4, callID: "input", output: "cancelled"))
    try fixture.append(inputRecord(type: "function_call", second: 5, callID: "next", name: "request_user_input"))
    try fixture.append(inputRecord(type: "function_call_output", second: 6, callID: "next", output: "answer"))
    #expect(try provider.poll().logEvents.map(\.kind) == [.responseInProgress])
}

@Test(arguments: ["task_complete", "turn_aborted", "task_started"])
func codexInputClearedByTaskLifecycle(type: String) throws {
    let fixture = try CompletionFixture()
    defer { fixture.remove() }
    try fixture.append(lifecycleLine("task_started", second: 1))
    let provider = fixture.provider()
    _ = try provider.poll()
    try fixture.append(inputRecord(type: "function_call", second: 2, callID: "input", name: "request_user_input_async"))
    #expect(try provider.poll().logEvents.map(\.kind) == [.userInputRequested])
    try fixture.append(lifecycleLine(type, second: 3))
    #expect(try provider.poll().logEvents.first?.kind != .userInputRequested)
}

@Test
func codexInputIgnoresOrdinaryToolsAndFailedAsyncRequests() throws {
    let fixture = try CompletionFixture()
    defer { fixture.remove() }
    try fixture.append(lifecycleLine("task_started", second: 1))
    let provider = fixture.provider()
    _ = try provider.poll()
    try fixture.append(inputRecord(type: "function_call", second: 2, callID: "tool", name: "exec_command"))
    #expect(try provider.poll().logEvents.isEmpty)
    try fixture.append(inputRecord(type: "function_call", second: 3, callID: "input", name: "request_user_input_async"))
    try fixture.append(inputRecord(type: "function_call_output", second: 4, callID: "input", output: "{\"accepted\":false}"))
    #expect(try provider.poll().logEvents.map(\.kind) == [.responseInProgress])
}

@MainActor
@Test
func codexInputPipelinePlaysOncePerRequestAndRespectsMute() throws {
    let fixture = try CompletionFixture()
    defer { fixture.remove() }
    let suiteName = UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let soundStore = SoundPreferenceStore(userDefaults: defaults)
    let customURL = URL(fileURLWithPath: "/tmp/input-sound.wav")
    soundStore.customCompletionSoundURL = customURL
    var sounds = 0
    var banners = 0
    let manager = NotificationManager(
        soundPreferenceStore: soundStore,
        bannerPresenter: { _, _ in banners += 1 },
        soundPlayer: { url in
            #expect(url == customURL)
            sounds += 1
        }
    )
    let coordinator = SessionCoordinator()
    let provider = fixture.provider()
    try fixture.append(lifecycleLine("task_started", second: 1))
    let initial = try provider.poll()
    coordinator.apply(threadSnapshots: initial.threadSnapshots)
    coordinator.apply(logEvents: initial.logEvents)
    try fixture.append(inputRecord(type: "function_call", second: 2, callID: "input", name: "request_user_input"))
    coordinator.apply(logEvents: try provider.poll().logEvents)
    #expect(coordinator.currentSnapshot.statusText == "Waiting for input")
    #expect(coordinator.pendingCompletion == nil)
    let firstRequest = try #require(coordinator.pendingUserInput)
    manager.notifyUserInputRequested()
    coordinator.consumeUserInputNotification(for: firstRequest)
    coordinator.apply(logEvents: try provider.poll().logEvents)
    #expect(coordinator.pendingUserInput == nil)
    #expect(sounds == 1)

    // A distinct request seconds later must not be lost to the completion cooldown.
    try fixture.append(inputRecord(type: "function_call_output", second: 3, callID: "input", output: "answer"))
    try fixture.append(inputRecord(type: "function_call", second: 4, callID: "next", name: "request_user_input"))
    let next = try provider.poll()
    coordinator.apply(logEvents: next.logEvents)
    let secondRequest = try #require(coordinator.pendingUserInput)
    manager.notifyUserInputRequested()
    coordinator.consumeUserInputNotification(for: secondRequest)
    #expect(coordinator.pendingUserInput == nil)
    #expect(sounds == 2)
    soundStore.isSoundEnabled = false
    manager.notifyUserInputRequested()
    #expect(sounds == 2)
    #expect(banners == 0)
}

@Test
func inputNotificationIsIndependentOfOtherActiveSessionsAndCompletion() async {
    let now = Date()
    let coordinator = SessionCoordinator(now: { now })
    coordinator.apply(threadSnapshots: ["input", "running", "done"].map {
        ThreadSnapshot(threadID: $0, title: $0, source: "desktop", cwd: nil, updatedAt: now.addingTimeInterval(-10))
    })
    coordinator.apply(logEvents: [
        CodexLogEvent(threadID: "input", kind: .userInputRequested, toolName: nil, summary: "Input", timestamp: now),
        CodexLogEvent(threadID: "running", kind: .toolStarted, toolName: "exec", summary: "Tool", timestamp: now),
        CodexLogEvent(threadID: "done", kind: .responseCompleted, toolName: nil, summary: "Done", timestamp: now.addingTimeInterval(-10)),
    ])
    let engine = PollingEngine(coordinator: coordinator, providers: [])
    let result = await engine.pollOnce()
    #expect(result.userInputNotification?.threadID == "input")
    #expect(result.completionNotification?.threadID == "done")
    #expect(result.snapshot.primaryThreadID == "input")
    if let request = result.userInputNotification {
        await engine.consumeUserInputNotification(for: request)
    }
    #expect(await engine.pollOnce().userInputNotification == nil)
    #expect(InterfaceLanguage.simplifiedChinese.statusText(for: "Waiting for input") == "等待输入")
    #expect(InterfaceLanguage.english.compactStatusText(for: "Waiting for input") == "Input needed")
    #expect(IslandStatusPresentation.compactTone(for: "Waiting for input") == .tool)
}

@Test
func codexInputResumeRetainsToolLogsAndTaskCompletion() throws {
    let fixture = try CompletionFixture()
    defer { fixture.remove() }
    try fixture.append(lifecycleLine("task_started", second: 1))
    try fixture.append(inputRecord(type: "function_call", second: 2, callID: "input", name: "request_user_input"))
    try fixture.append(inputRecord(type: "function_call_output", second: 3, callID: "input", output: "answer"))
    try fixture.execute(
        "insert into logs values (1, \(Int(fixture.start.timeIntervalSince1970) + 4), 'INFO', 'test', 'response.in_progress', 'thread-1', null)",
        at: fixture.logs
    )
    let provider = fixture.provider()
    #expect(try provider.poll().logEvents.count == 2)
    try fixture.append(lifecycleLine("task_complete", second: 5))
    #expect(try provider.poll().logEvents.map(\.kind) == [.taskCompleted])
}

@Test
func codexTaskCompletionNotifiesOnFirstPollWithoutQuietTime() async throws {
    let fixture = try CompletionFixture()
    defer { fixture.remove() }
    let completionTime = fixture.start.addingTimeInterval(10.123)
    let provider = fixture.provider()
    try fixture.append(lifecycleLine("task_started", second: 1))
    #expect(try provider.poll().logEvents.map(\.kind) == [.responseCreated])
    let engine = PollingEngine(
        coordinator: SessionCoordinator(now: { completionTime }),
        providers: [provider]
    )
    try fixture.append(lifecycleLine("task_complete", second: 10))
    let result = await engine.pollOnce()
    #expect(result.completionNotification?.threadID == "thread-1")
    #expect(result.snapshot.statusText == "Done")
    await engine.consumeCompletionNotification(for: "thread-1")
    #expect(await engine.pollOnce().completionNotification == nil)
}

@Test
func codexTaskCompletionIgnoresMetadataDelayButNewTurnCancelsIt() throws {
    let fixture = try CompletionFixture()
    defer { fixture.remove() }
    let coordinator = SessionCoordinator(now: { fixture.start.addingTimeInterval(10.123) })
    let provider = fixture.provider()
    try fixture.append(lifecycleLine("task_complete", second: 10))
    let completed = try provider.poll()
    coordinator.apply(threadSnapshots: completed.threadSnapshots)
    coordinator.apply(logEvents: completed.logEvents)
    // Metadata can be persisted after the terminal record; it does not reopen a task.
    coordinator.apply(threadSnapshots: [ThreadSnapshot(
        threadID: "thread-1", title: "Updated title", source: "desktop", cwd: nil,
        updatedAt: fixture.start.addingTimeInterval(11)
    )])
    #expect(coordinator.pendingCompletion?.threadID == "thread-1")
    try fixture.append(lifecycleLine("task_started", second: 12))
    coordinator.apply(logEvents: try provider.poll().logEvents)
    #expect(coordinator.pendingCompletion == nil)
    #expect(coordinator.currentSnapshot.statusText == "Running")
}

@Test
func codexDiagnosticCompletionStillWaitsForQuietTime() async throws {
    let fixture = try CompletionFixture()
    defer { fixture.remove() }
    try fixture.execute(
        "insert into logs values (1, \(Int(fixture.start.timeIntervalSince1970) + 2), 'INFO', 'test', 'response.completed', 'thread-1', null)",
        at: fixture.logs
    )
    let engine = PollingEngine(
        coordinator: SessionCoordinator(now: { fixture.start.addingTimeInterval(2) }),
        providers: [fixture.provider()]
    )
    let result = await engine.pollOnce()
    #expect(result.completionNotification == nil)
    #expect(result.snapshot.statusText == "Running")
}
