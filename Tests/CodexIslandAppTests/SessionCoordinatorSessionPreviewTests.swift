import Foundation
import Testing
@testable import CodexIslandCore

@Test
func sessionCoordinatorBuildsRecentSessionPreviews() {
    let coordinator = SessionCoordinator(now: { Date(timeIntervalSince1970: 400) })
    let older = ThreadSnapshot(
        threadID: "thread-1",
        title: "旧会话",
        source: "desktop",
        cwd: "/tmp/old",
        updatedAt: Date(timeIntervalSince1970: 200),
        firstUserMessage: "帮我看一下老问题"
    )
    let newer = ThreadSnapshot(
        threadID: "thread-2",
        title: "新会话",
        source: "desktop",
        cwd: "/tmp/new",
        updatedAt: Date(timeIntervalSince1970: 300),
        firstUserMessage: "参考这个，可以大致的看到每个session的内容"
    )
    let assistantMessage = SessionMessagePreview(
        threadID: "thread-2",
        author: .assistant,
        text: "我会把展开态改成多 session 列表。",
        timestamp: Date(timeIntervalSince1970: 320)
    )
    let toolEvent = CodexLogEvent(
        threadID: "thread-2",
        kind: .toolUpdated,
        toolName: "exec_command",
        summary: "sqlite3 ~/.codex/logs_2.sqlite",
        timestamp: Date(timeIntervalSince1970: 330)
    )

    coordinator.apply(threadSnapshots: [older, newer])
    coordinator.apply(messagePreviews: [assistantMessage])
    coordinator.apply(logEvents: [toolEvent])

    let snapshot = coordinator.currentSnapshot

    #expect(snapshot.sessionPreviews.count == 2)
    #expect(snapshot.sessionPreviews.first?.threadID == "thread-2")
    #expect(snapshot.sessionPreviews.first?.userPreview == "参考这个，可以大致的看到每个session的内容")
    #expect(snapshot.sessionPreviews.first?.assistantPreview == "我会把展开态改成多 session 列表。")
    #expect(snapshot.sessionPreviews.first?.latestToolSummary == "sqlite3 ~/.codex/logs_2.sqlite")
    #expect(snapshot.sessionPreviews.first?.isPrimary == true)
}

@Test
func sessionCoordinatorSanitizesFallbackUserPreview() {
    let coordinator = SessionCoordinator(now: { Date(timeIntervalSince1970: 500) })
    let snapshot = ThreadSnapshot(
        threadID: "thread-9",
        title: "敏感回退",
        source: "desktop",
        cwd: "/tmp/secure",
        updatedAt: Date(timeIntervalSince1970: 480),
        firstUserMessage: "客服反馈手机号 15081633966，身份证号 130403199306022722，需要确认这个会话摘要不会直接暴露原文。"
    )

    coordinator.apply(threadSnapshots: [snapshot])

    let islandSnapshot = coordinator.currentSnapshot
    let preview = islandSnapshot.sessionPreviews.first

    #expect(preview?.userPreview?.contains("1**********") == true)
    #expect(preview?.userPreview?.contains("******************") == true)
    #expect(preview?.userPreview?.contains("15081633966") == false)
    #expect(preview?.userPreview?.contains("130403199306022722") == false)
}

@Test
func sessionCoordinatorSanitizesSessionTitle() {
    let coordinator = SessionCoordinator(now: { Date(timeIntervalSince1970: 600) })
    let snapshot = ThreadSnapshot(
        threadID: "thread-10",
        title: "客服反馈用户提交认领入驻申请，手机号 15081633966，身份证号 130403199306022722，需要看这个标题是否会被摘要化",
        source: "desktop",
        cwd: "/tmp/title",
        updatedAt: Date(timeIntervalSince1970: 590),
        firstUserMessage: nil
    )

    coordinator.apply(threadSnapshots: [snapshot])

    let islandSnapshot = coordinator.currentSnapshot

    #expect(islandSnapshot.threadTitle.contains("1**********"))
    #expect(islandSnapshot.threadTitle.contains("******************"))
    #expect(!islandSnapshot.threadTitle.contains("15081633966"))
    #expect(!islandSnapshot.threadTitle.contains("130403199306022722"))
}
