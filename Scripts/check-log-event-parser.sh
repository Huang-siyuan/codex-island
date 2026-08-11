#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat <<'SWIFT' >"$TMP_DIR/ParserRegression.swift"
import Foundation

@main
struct ParserRegression {
    static func main() {
        let parser = LogsEventParser()
        let threadID = "Jackm"

        assertEvent(
            parser.parse(row: LogRow(
                id: 1,
                timestamp: 1776247467,
                level: "info",
                target: "codex_api::endpoint::responses_websocket",
                body: #"session_loop{thread_id=Jackm}: websocket event: {"type":"response.in_progress"}"#,
                threadID: threadID,
                processUUID: nil
            )),
            expectedKind: .responseInProgress
        )

        assertEvent(
            parser.parse(row: LogRow(
                id: 2,
                timestamp: 1776247490,
                level: "info",
                target: "codex_api::endpoint::responses_websocket",
                body: #"session_loop{thread_id=Jackm}: websocket event: {"type":"response.output_item.added","item":{"id":"fc_Jackm","type":"function_call","status":"in_progress","arguments":"","call_id":"call_Jackm","name":"exec_command"},"output_index":2,"sequence_number":86}"#,
                threadID: threadID,
                processUUID: nil
            )),
            expectedKind: .toolStarted,
            summaryContains: "Tool call"
        )

        assertEvent(
            parser.parse(row: LogRow(
                id: 3,
                timestamp: 1776247490,
                level: "info",
                target: "codex_api::endpoint::responses_websocket",
                body: #"session_loop{thread_id=Jackm}: websocket event: {"type":"response.function_call_arguments.done","arguments":"{\"cmd\":\"sqlite3 -line /Users/Jackm/.codex/logs_2.sqlite \\\"select id from logs limit 1;\\\"\",\"workdir\":\"/Users/Jackm/Projects\"}","item_id":"fc_Jackm","output_index":2,"sequence_number":88}"#,
                threadID: threadID,
                processUUID: nil
            )),
            expectedKind: .toolUpdated,
            summaryContains: "sqlite3 -line"
        )

        assertEvent(
            parser.parse(row: LogRow(
                id: 4,
                timestamp: 1776247490,
                level: "info",
                target: "codex_api::endpoint::responses_websocket",
                body: #"session_loop{thread_id=Jackm}: websocket event: {"type":"response.output_item.done","item":{"id":"msg_Jackm","type":"message","status":"completed","content":[{"type":"output_text","annotations":[],"logprobs":[],"text":"hello"}],"phase":"commentary","role":"assistant"},"output_index":1,"sequence_number":85}"#,
                threadID: threadID,
                processUUID: nil
            )),
            expectedKind: .responseInProgress,
            summaryContains: "Assistant response"
        )

        assertEvent(
            parser.parse(row: LogRow(
                id: 5,
                timestamp: 1776247500,
                level: "info",
                target: "codex_api::sse::responses",
                body: #"session_loop{thread_id=Jackm}: responses_websocket.stream_request: unhandled responses event: response.completed"#,
                threadID: threadID,
                processUUID: nil
            )),
            expectedKind: .responseCompleted
        )

        print("Log event parser check passed.")
    }

    private static func assertEvent(
        _ event: CodexLogEvent?,
        expectedKind: CodexLogEventKind,
        summaryContains: String? = nil
    ) {
        guard let event else {
            fputs("Expected event kind \(expectedKind.rawValue), got nil.\n", stderr)
            exit(1)
        }

        guard event.kind == expectedKind else {
            fputs("Expected event kind \(expectedKind.rawValue), got \(event.kind.rawValue).\n", stderr)
            exit(1)
        }

        if let summaryContains, !event.summary.contains(summaryContains) {
            fputs("Expected summary to contain '\(summaryContains)', got '\(event.summary)'.\n", stderr)
            exit(1)
        }
    }
}
SWIFT

swiftc \
  "$ROOT/Sources/CodexIslandCore/CodexModels.swift" \
  "$ROOT/Sources/CodexIslandCore/LogsEventParser.swift" \
  "$TMP_DIR/ParserRegression.swift" \
  -o "$TMP_DIR/parser-regression"

"$TMP_DIR/parser-regression"
