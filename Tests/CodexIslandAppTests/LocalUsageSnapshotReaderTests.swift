import Foundation
import Testing
@testable import CodexIslandCore

@Test
func localUsageSnapshotReaderAccumulatesTotalUsageByDelta() throws {
    let root = try makeSessionsRoot(dayKey: "2026-08-08", fileName: "usage-total.jsonl", lines: [
        #"{"type":"turn_context","payload":{"model":"gpt-5"}}"#,
        #"{"type":"event_msg","timestamp":"2026-08-08T10:00:00Z","payload":{"type":"agent_message","message":"Starting"}}"#,
        #"{"type":"event_msg","timestamp":"2026-08-08T10:00:02Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":60,"output_tokens":20}}}}"#,
        #"{"type":"event_msg","timestamp":"2026-08-08T10:00:04Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":130,"cached_input_tokens":70,"output_tokens":40}}}}"#
    ])

    let reader = LocalUsageSnapshotReader(
        sessionsRoots: [root],
        now: { fixedNow(dayKey: "2026-08-08") }
    )

    let snapshot = reader.readSnapshot(days: 7)
    let today = try #require(snapshot.days.last)

    #expect(today.inputTokens == 130)
    #expect(today.cachedInputTokens == 70)
    #expect(today.outputTokens == 40)
    #expect(today.totalTokens == 170)
    #expect(today.agentRuns == 1)
    #expect(today.agentTimeMS == 4_000)
    #expect(snapshot.totals.last7DaysTokens == 170)
    #expect(snapshot.topModels.first?.model == "gpt-5")
    #expect(snapshot.topModels.first?.tokens == 170)
}

@Test
func localUsageSnapshotReaderTracksRunsAndActivityFromIncrementalEvents() throws {
    let root = try makeSessionsRoot(dayKey: "2026-08-08", fileName: "usage-last.jsonl", lines: [
        #"{"type":"event_msg","timestamp":"2026-08-08T11:00:00Z","payload":{"type":"agent_message","message":"Starting"}}"#,
        #"{"type":"event_msg","timestamp":"2026-08-08T11:00:03Z","payload":{"type":"agent_reasoning","text":"Thinking"}}"#,
        #"{"type":"response_item","timestamp":"2026-08-08T11:00:05Z","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Done"}]}}"#,
        #"{"type":"event_msg","timestamp":"2026-08-08T11:00:06Z","payload":{"type":"token_count","info":{"model":"gpt-5.6","last_token_usage":{"input_tokens":10,"cached_input_tokens":5,"output_tokens":2}}}}"#,
        #"{"type":"event_msg","timestamp":"2026-08-08T11:00:08Z","payload":{"type":"token_count","info":{"model":"gpt-5.6","last_token_usage":{"input_tokens":15,"cached_input_tokens":7,"output_tokens":3}}}}"#
    ])

    let reader = LocalUsageSnapshotReader(
        sessionsRoots: [root],
        now: { fixedNow(dayKey: "2026-08-08") }
    )

    let snapshot = reader.readSnapshot(days: 7)
    let today = try #require(snapshot.days.last)

    #expect(today.inputTokens == 25)
    #expect(today.cachedInputTokens == 12)
    #expect(today.outputTokens == 5)
    #expect(today.totalTokens == 30)
    #expect(today.agentRuns == 2)
    #expect(today.agentTimeMS == 8_000)
    #expect(snapshot.totals.cacheHitRatePercent == 48)
    #expect(snapshot.topModels.first?.model == "gpt-5.6")
    #expect(snapshot.topModels.first?.sharePercent == 100)
}

@Test
func localUsageSnapshotReaderGroupsAndFiltersUsageByWorkspace() throws {
    let root = try makeSessionsRoot(dayKey: "2026-08-08", fileName: "workspace-a.jsonl", lines: [
        #"{"type":"session_meta","payload":{"cwd":"/Users/demo/project-a/Sources/Feature"}}"#,
        #"{"type":"turn_context","payload":{"model":"gpt-a"}}"#,
        #"{"type":"event_msg","timestamp":"2026-08-08T10:00:00Z","payload":{"type":"agent_message","message":"Starting"}}"#,
        #"{"type":"event_msg","timestamp":"2026-08-08T10:00:02Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":10}}}}"#
    ])
    let dayDirectory = directoryURL(for: "2026-08-08", under: root)
    try [
        #"{"type":"session_meta","payload":{"cwd":"/Users/demo/project-b"}}"#,
        #"{"type":"turn_context","payload":{"model":"gpt-b"}}"#,
        #"{"type":"event_msg","timestamp":"2026-08-08T11:00:00Z","payload":{"type":"agent_message","message":"Starting"}}"#,
        #"{"type":"event_msg","timestamp":"2026-08-08T11:00:03Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":200,"cached_input_tokens":40,"output_tokens":20}}}}"#
    ]
    .joined(separator: "\n")
    .write(
        to: dayDirectory.appendingPathComponent("workspace-b.jsonl"),
        atomically: true,
        encoding: .utf8
    )
    try [
        #"{"type":"session_meta","payload":{"cwd":"/Users/demo/not-imported"}}"#,
        #"{"type":"turn_context","payload":{"model":"gpt-ignored"}}"#,
        #"{"type":"event_msg","timestamp":"2026-08-08T12:00:00Z","payload":{"type":"agent_message","message":"Starting"}}"#,
        #"{"type":"event_msg","timestamp":"2026-08-08T12:00:01Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":300,"cached_input_tokens":60,"output_tokens":30}}}}"#
    ]
    .joined(separator: "\n")
    .write(
        to: dayDirectory.appendingPathComponent("workspace-ignored.jsonl"),
        atomically: true,
        encoding: .utf8
    )

    let reader = LocalUsageSnapshotReader(
        sessionsRoots: [root],
        savedWorkspaceRoots: [
            URL(fileURLWithPath: "/Users/demo/project-a", isDirectory: true),
            URL(fileURLWithPath: "/Users/demo/project-b", isDirectory: true),
            URL(fileURLWithPath: "/Users/demo/project-c", isDirectory: true),
        ],
        now: { fixedNow(dayKey: "2026-08-08") }
    )

    let snapshot = reader.readSnapshot(days: 7)
    let projectA = try #require(snapshot.workspaces.first(where: { $0.name == "project-a" }))
    let filtered = snapshot.filtered(toWorkspaceID: projectA.id)

    #expect(snapshot.workspaces.map(\.name) == ["project-a", "project-b", "project-c"])
    #expect(snapshot.days.last?.totalTokens == 330)
    #expect(filtered.days.last?.totalTokens == 110)
    #expect(filtered.days.last?.agentRuns == 1)
    #expect(filtered.topModels.first?.model == "gpt-a")
    #expect(filtered.workspaces.count == 3)
}

private func makeSessionsRoot(dayKey: String, fileName: String, lines: [String]) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let dayDirectory = directoryURL(for: dayKey, under: root)
    try FileManager.default.createDirectory(at: dayDirectory, withIntermediateDirectories: true)
    let fileURL = dayDirectory.appendingPathComponent(fileName)
    try lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    return root
}

private func directoryURL(for dayKey: String, under root: URL) -> URL {
    let parts = dayKey.split(separator: "-")
    precondition(parts.count == 3)
    return root
        .appendingPathComponent(String(parts[0]), isDirectory: true)
        .appendingPathComponent(String(parts[1]), isDirectory: true)
        .appendingPathComponent(String(parts[2]), isDirectory: true)
}

private func fixedNow(dayKey: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: "\(dayKey)T12:00:00Z") ?? Date(timeIntervalSince1970: 0)
}
