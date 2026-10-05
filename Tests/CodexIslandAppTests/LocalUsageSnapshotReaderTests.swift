import Foundation
import Testing
@testable import CodexIslandCore

@Test
func usageSnapshotLoaderDetectsDayRollover() async throws {
    let cacheURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent("usage-snapshot.json")
    try FileManager.default.createDirectory(
        at: cacheURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let previousDay = fixedNow(dayKey: "2026-08-18")
    let snapshot = LocalUsageSnapshot.empty(days: 30, now: previousDay)
    try JSONEncoder().encode(snapshot).write(to: cacheURL)
    let loader = UsageSnapshotLoader(cacheURL: cacheURL)

    #expect(await !loader.needsRefreshForCurrentDay(now: previousDay))
    #expect(await loader.needsRefreshForCurrentDay(now: fixedNow(dayKey: "2026-08-19")))
}

@Test(arguments: [Int?.none, 1])
func usageSnapshotLoaderRebuildsRecentProjectOnlyCache(schemaVersion: Int?) async throws {
    let root = try makeSessionsRoot(dayKey: "2026-08-08", fileName: "topic.jsonl", lines: [
        #"{"type":"event_msg","timestamp":"2026-08-08T10:00:00Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":10}}}}"#
    ])
    let now = fixedNow(dayKey: "2026-08-08")
    let cacheURL = root.appendingPathComponent("usage-snapshot.json")
    let oldSnapshot = LocalUsageSnapshot.empty(days: 30, now: now)
    // Simulate historical on-disk schemas that the current Codable model cannot produce.
    var oldCache = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(oldSnapshot)) as? [String: Any]
    )
    if let schemaVersion {
        oldCache["schemaVersion"] = schemaVersion
    } else {
        oldCache.removeValue(forKey: "schemaVersion")
    }
    try JSONSerialization.data(withJSONObject: oldCache).write(to: cacheURL)
    let reader = LocalUsageSnapshotReader(sessionsRoots: [root], savedWorkspaceRoots: [], now: { now })
    let loader = UsageSnapshotLoader(reader: reader, cacheURL: cacheURL)

    #expect(await loader.cached() == nil)
    #expect(await loader.needsRefreshForCurrentDay(now: now))
    let refreshed = await loader.snapshot(now: now)
    #expect(refreshed.schemaVersion == LocalUsageSnapshot.currentSchemaVersion)
    #expect(refreshed.totals.last30DaysTokens == 110)
    #expect(refreshed.workspaces.first?.isUnassigned == true)

    let reloadedReader = LocalUsageSnapshotReader(sessionsRoots: [root], savedWorkspaceRoots: [], now: { now })
    let reloaded = UsageSnapshotLoader(reader: reloadedReader, cacheURL: cacheURL)
    #expect(await reloaded.cached() == refreshed)
    #expect(await !reloaded.needsRefreshForCurrentDay(now: now))
    #expect(await reloaded.snapshot(now: now) == refreshed)
}

@Test
func usageSnapshotLoaderManualRefreshBypassesAndReplacesRecentCache() async throws {
    let root = try makeSessionsRoot(dayKey: "2026-08-08", fileName: "usage-growing.jsonl", lines: [
        #"{"type":"turn_context","payload":{"model":"gpt-5"}}"#,
        #"{"type":"event_msg","timestamp":"2026-08-08T10:00:00Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":10}}}}"#,
        "",
    ])
    defer { try? FileManager.default.removeItem(at: root) }
    let now = fixedNow(dayKey: "2026-08-08")
    let cacheURL = root.appendingPathComponent("usage-snapshot.json")
    let reader = LocalUsageSnapshotReader(sessionsRoots: [root], savedWorkspaceRoots: [], now: { now })
    let loader = UsageSnapshotLoader(reader: reader, cacheURL: cacheURL)
    let initial = await loader.snapshot(now: now)
    #expect(initial.totals.last30DaysTokens == 110)

    let fileURL = directoryURL(for: "2026-08-08", under: root)
        .appendingPathComponent("usage-growing.jsonl")
    let handle = try FileHandle(forWritingTo: fileURL)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(
        #"{"type":"event_msg","timestamp":"2026-08-08T10:00:02Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":30,"cached_input_tokens":5,"output_tokens":3}}}}"#.utf8
    ))
    try handle.close()

    let refreshTime = now.addingTimeInterval(60)
    #expect(await loader.snapshot(now: refreshTime) == initial)
    let refreshed = await loader.snapshot(forceRefresh: true, now: refreshTime)
    #expect(refreshed.days.last?.inputTokens == 130)
    #expect(refreshed.days.last?.cachedInputTokens == 25)
    #expect(refreshed.days.last?.outputTokens == 13)
    #expect(refreshed.totals.last30DaysTokens == 143)
    #expect(refreshed.workspaces.first?.totals.last30DaysTokens == 143)
    #expect(await loader.cached() == refreshed)
    #expect(await loader.snapshot(now: refreshTime.addingTimeInterval(60)) == refreshed)
    #expect(await loader.snapshot(forceRefresh: true, now: refreshTime.addingTimeInterval(120)) == refreshed)

    let reloadedReader = LocalUsageSnapshotReader(sessionsRoots: [root], savedWorkspaceRoots: [], now: { now })
    let reloaded = UsageSnapshotLoader(reader: reloadedReader, cacheURL: cacheURL)
    #expect(await reloaded.cached() == refreshed)
    #expect(await reloaded.snapshot(now: refreshTime.addingTimeInterval(180)) == refreshed)
}

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
func localUsageSnapshotReaderAddsOnlyAppendedEventsOnRefresh() throws {
    let root = try makeSessionsRoot(dayKey: "2026-08-08", fileName: "usage-growing.jsonl", lines: [
        #"{"type":"turn_context","payload":{"model":"gpt-5"}}"#,
        #"{"type":"event_msg","timestamp":"2026-08-08T10:00:00Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":10}}}}"#,
        "",
    ])
    let fileURL = directoryURL(for: "2026-08-08", under: root)
        .appendingPathComponent("usage-growing.jsonl")
    let reader = LocalUsageSnapshotReader(
        sessionsRoots: [root],
        now: { fixedNow(dayKey: "2026-08-08") }
    )

    #expect(reader.readSnapshot(days: 7).days.last?.totalTokens == 110)

    let handle = try FileHandle(forWritingTo: fileURL)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(
        #"{"type":"event_msg","timestamp":"2026-08-08T10:00:02Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":30,"cached_input_tokens":5,"output_tokens":3}}}}"#.utf8
    ))
    try handle.close()

    let refreshed = reader.readSnapshot(days: 7)
    #expect(refreshed.days.last?.inputTokens == 130)
    #expect(refreshed.days.last?.cachedInputTokens == 25)
    #expect(refreshed.days.last?.outputTokens == 13)
    #expect(refreshed.days.last?.totalTokens == 143)
    #expect(refreshed.workspaces.count == 1)
    #expect(refreshed.workspaces.first?.isUnassigned == true)
    #expect(refreshed.filtered(toWorkspaceID: LocalUsageWorkspace.unassignedID).days == refreshed.days)
    #expect(reader.readSnapshot(days: 7) == refreshed)
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
        #"{"type":"turn_context","payload":{"model":"gpt-topic"}}"#,
        #"{"type":"event_msg","timestamp":"2026-08-08T12:00:00Z","payload":{"type":"agent_message","message":"Starting"}}"#,
        #"{"type":"event_msg","timestamp":"2026-08-08T12:00:01Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":300,"cached_input_tokens":60,"output_tokens":30}}}}"#
    ]
    .joined(separator: "\n")
    .write(
        to: dayDirectory.appendingPathComponent("topic.jsonl"),
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
    let topic = try #require(snapshot.workspaces.first(where: { $0.isUnassigned }))
    let topicSnapshot = snapshot.filtered(toWorkspaceID: topic.id)

    #expect(snapshot.workspaces.map(\.name) == ["project-a", "project-b", "project-c", "Topics / No project"])
    #expect(snapshot.days.last?.totalTokens == 660)
    #expect(filtered.days.last?.totalTokens == 110)
    #expect(filtered.days.last?.agentRuns == 1)
    #expect(filtered.topModels.first?.model == "gpt-a")
    #expect(filtered.workspaces.count == 4)
    #expect(topic.id == LocalUsageWorkspace.unassignedID)
    #expect(topicSnapshot.days.last?.totalTokens == 330)
    #expect(topicSnapshot.topModels.first?.model == "gpt-topic")
    #expect(snapshot.workspaces.first(where: { $0.name == "project-c" })?.totals.last7DaysTokens == 0)

    let today = try #require(snapshot.days.last)
    let scopedDays = snapshot.workspaces.compactMap { $0.days.last }
    #expect(today.inputTokens == 600)
    #expect(today.cachedInputTokens == 120)
    #expect(today.outputTokens == 60)
    #expect(today.agentRuns == 3)
    #expect(today.agentTimeMS == 6_000)
    #expect(today.inputTokens == scopedDays.reduce(0) { $0 + $1.inputTokens })
    #expect(today.cachedInputTokens == scopedDays.reduce(0) { $0 + $1.cachedInputTokens })
    #expect(today.outputTokens == scopedDays.reduce(0) { $0 + $1.outputTokens })
    #expect(today.totalTokens == scopedDays.reduce(0) { $0 + $1.totalTokens })
    #expect(today.agentRuns == scopedDays.reduce(0) { $0 + $1.agentRuns })
    #expect(today.agentTimeMS == scopedDays.reduce(0) { $0 + $1.agentTimeMS })
    #expect(snapshot.totals.last7DaysTokens == 660)
    #expect(snapshot.totals.last30DaysTokens == 660)
    #expect(snapshot.totals.cacheHitRatePercent == 20)
    for model in snapshot.topModels {
        let scopedTokens = snapshot.workspaces.flatMap(\.topModels)
            .filter { $0.model == model.model }
            .reduce(0) { $0 + $1.tokens }
        #expect(model.tokens == scopedTokens)
    }
}

@Test(arguments: [
    "",
    #"{"type":"session_meta","payload":{"cwd":""}}"#,
    #"{"type":"session_meta","payload":{"cwd":"   "}}"#,
    #"{"type":"session_meta","payload":{"cwd":"/Users/demo/Documents/Codex/topic-a"}}"#,
])
func localUsageSnapshotReaderIncludesUsageWithoutImportedProjects(metadata: String) throws {
    let root = try makeSessionsRoot(dayKey: "2026-08-08", fileName: "topic.jsonl", lines: [
        metadata,
        #"{"type":"turn_context","payload":{"model":"gpt-topic"}}"#,
        #"{"type":"event_msg","timestamp":"2026-08-08T10:00:00Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":10}}}}"#
    ])
    let reader = LocalUsageSnapshotReader(
        sessionsRoots: [root],
        savedWorkspaceRoots: [],
        now: { fixedNow(dayKey: "2026-08-08") }
    )

    let snapshot = reader.readSnapshot(days: 7)
    let topic = try #require(snapshot.workspaces.first)
    #expect(snapshot.totals.last7DaysTokens == 110)
    #expect(snapshot.workspaces.count == 1)
    #expect(topic.isUnassigned)
    #expect(topic.name == "Topics / No project")
    #expect(topic.days == snapshot.days)
    #expect(topic.totals == snapshot.totals)
    #expect(topic.topModels == snapshot.topModels)
}

@Test
func localUsageSnapshotReaderKeepsRawWorkspaceGroupingWhenRootsAreUnspecified() throws {
    let root = try makeSessionsRoot(dayKey: "2026-08-08", fileName: "topic.jsonl", lines: [
        #"{"type":"session_meta","payload":{"cwd":"/Users/demo/project-a"}}"#,
        #"{"type":"event_msg","timestamp":"2026-08-08T10:00:00Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"output_tokens":10}}}}"#
    ])
    let reader = LocalUsageSnapshotReader(
        sessionsRoots: [root],
        now: { fixedNow(dayKey: "2026-08-08") }
    )

    let snapshot = reader.readSnapshot(days: 7)
    #expect(snapshot.workspaces.count == 1)
    #expect(snapshot.workspaces.first?.path == "/Users/demo/project-a")
    #expect(snapshot.workspaces.first?.isUnassigned == false)
    #expect(snapshot.workspaces.first?.totals.last7DaysTokens == 110)
}

@Test
func localUsageSnapshotReaderUsesDeepestProjectRootAndRejectsSiblingPrefixes() throws {
    let sessions = [
        ("/Users/demo/project/nested/Sources", 100),
        ("/Users/demo/project-other", 200),
        ("/Users/demo/project/Sources", 300),
    ]
    let root = try makeSessionsRoot(dayKey: "2026-08-08", fileName: "empty.jsonl", lines: [])
    let dayDirectory = directoryURL(for: "2026-08-08", under: root)
    for (index, session) in sessions.enumerated() {
        try [
            #"{"type":"session_meta","payload":{"cwd":"\#(session.0)"}}"#,
            #"{"type":"event_msg","timestamp":"2026-08-08T10:00:00Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":\#(session.1),"output_tokens":10}}}}"#,
        ]
        .joined(separator: "\n")
        .write(to: dayDirectory.appendingPathComponent("session-\(index).jsonl"), atomically: true, encoding: .utf8)
    }
    let reader = LocalUsageSnapshotReader(
        sessionsRoots: [root],
        savedWorkspaceRoots: [
            URL(fileURLWithPath: "/Users/demo/project", isDirectory: true),
            URL(fileURLWithPath: "/Users/demo/project/nested", isDirectory: true),
        ],
        now: { fixedNow(dayKey: "2026-08-08") }
    )

    let snapshot = reader.readSnapshot(days: 7)
    #expect(snapshot.totals.last7DaysTokens == 630)
    #expect(snapshot.workspaces.count == 3)
    #expect(snapshot.filtered(toWorkspaceID: "/Users/demo/project/nested").totals.last7DaysTokens == 110)
    #expect(snapshot.filtered(toWorkspaceID: "/Users/demo/project").totals.last7DaysTokens == 310)
    #expect(snapshot.filtered(toWorkspaceID: LocalUsageWorkspace.unassignedID).totals.last7DaysTokens == 210)
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
