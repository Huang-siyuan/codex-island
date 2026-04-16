import Foundation
import Testing
@testable import CodexIslandCore

@Test
func logsEventParserExtractsToolActivityFromCodexLogMessage() throws {
    let row = LogRow(
        id: 42,
        timestamp: 1_776_241_264,
        level: "TRACE",
        target: "log",
        body: #"Received message {"type":"response.function_call_arguments.done","arguments":"{\"cmd\":\"osascript -e 'id of app \\\"IntelliJ IDEA\\\"'\"}","item_id":"fc_1","sequence_number":98}"#,
        threadID: "thread-1",
        processUUID: "proc-1"
    )

    let event = try #require(LogsEventParser().parse(row: row))

    #expect(event.threadID == "thread-1")
    #expect(event.kind == .toolUpdated)
    #expect(event.toolName == "exec_command")
    #expect(event.summary.contains("IntelliJ IDEA"))
}

@Test
func logsEventParserRecognizesResponseCompletion() throws {
    let row = LogRow(
        id: 84,
        timestamp: 1_776_241_497,
        level: "TRACE",
        target: "log",
        body: #"Received message {"type":"response.completed","response":{"status":"completed","completed_at":1776241497}}"#,
        threadID: "thread-1",
        processUUID: "proc-1"
    )

    let event = try #require(LogsEventParser().parse(row: row))

    #expect(event.kind == .responseCompleted)
}
