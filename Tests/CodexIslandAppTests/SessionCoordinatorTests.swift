import Foundation
import Testing
@testable import CodexIslandCore

@Test
func sessionCoordinatorPrefersNewestSessionAndCarriesLatestToolEvent() {
    let coordinator = SessionCoordinator(now: { Date(timeIntervalSince1970: 200) })
    let older = ThreadSnapshot(
        threadID: "a",
        title: "Old",
        source: "desktop",
        cwd: nil,
        updatedAt: Date(timeIntervalSince1970: 100),
        firstUserMessage: nil
    )
    let newer = ThreadSnapshot(
        threadID: "b",
        title: "New",
        source: "desktop",
        cwd: "/tmp/demo",
        updatedAt: Date(timeIntervalSince1970: 180),
        firstUserMessage: nil
    )
    let tool = CodexLogEvent(
        threadID: "b",
        kind: .toolUpdated,
        toolName: "exec_command",
        summary: "Run osascript",
        timestamp: Date(timeIntervalSince1970: 190)
    )

    coordinator.apply(threadSnapshots: [older, newer])
    coordinator.apply(logEvents: [tool])

    let viewState = coordinator.currentSnapshot
    #expect(viewState.primaryThreadID == "b")
    #expect(viewState.threadTitle == "New")
    #expect(viewState.latestToolSummary == "Run osascript")
    #expect(viewState.statusText == "Tool active")
}

@Test
func sessionCoordinatorWaitsForIdleBeforeMarkingCompletion() {
    var currentTime = Date(timeIntervalSince1970: 202)
    let coordinator = SessionCoordinator(
        now: { currentTime },
        completionIdleThreshold: 4,
        completionConfirmationThreshold: 2
    )
    let thread = ThreadSnapshot(
        threadID: "b",
        title: "New",
        source: "desktop",
        cwd: "/tmp/demo",
        updatedAt: Date(timeIntervalSince1970: 180),
        firstUserMessage: nil
    )
    let completion = CodexLogEvent(
        threadID: "b",
        kind: .responseCompleted,
        toolName: nil,
        summary: "Completed",
        timestamp: Date(timeIntervalSince1970: 200)
    )

    coordinator.apply(threadSnapshots: [thread])
    coordinator.apply(logEvents: [completion])

    #expect(coordinator.currentSnapshot.statusText == "Running")
    #expect(!coordinator.currentSnapshot.shouldNotifyCompletion)

    currentTime = Date(timeIntervalSince1970: 205)
    #expect(coordinator.currentSnapshot.statusText == "Running")
    #expect(!coordinator.currentSnapshot.shouldNotifyCompletion)

    currentTime = Date(timeIntervalSince1970: 207)
    #expect(coordinator.currentSnapshot.statusText == "Done")
    #expect(coordinator.currentSnapshot.shouldNotifyCompletion)

    coordinator.consumeCompletionNotification(for: "b")
    #expect(!coordinator.currentSnapshot.shouldNotifyCompletion)
}

@Test
func sessionCoordinatorClearsPendingCompletionWhenActivityResumes() {
    var currentTime = Date(timeIntervalSince1970: 210)
    let coordinator = SessionCoordinator(
        now: { currentTime },
        completionIdleThreshold: 4,
        completionConfirmationThreshold: 2
    )
    let thread = ThreadSnapshot(
        threadID: "b",
        title: "New",
        source: "desktop",
        cwd: "/tmp/demo",
        updatedAt: Date(timeIntervalSince1970: 180),
        firstUserMessage: nil
    )
    let completion = CodexLogEvent(
        threadID: "b",
        kind: .responseCompleted,
        toolName: nil,
        summary: "Completed",
        timestamp: Date(timeIntervalSince1970: 200)
    )
    let continuedWork = CodexLogEvent(
        threadID: "b",
        kind: .responseInProgress,
        toolName: nil,
        summary: "Working again",
        timestamp: Date(timeIntervalSince1970: 203)
    )

    coordinator.apply(threadSnapshots: [thread])
    coordinator.apply(logEvents: [completion, continuedWork])

    currentTime = Date(timeIntervalSince1970: 208)
    #expect(coordinator.currentSnapshot.statusText == "Running")
    #expect(!coordinator.currentSnapshot.shouldNotifyCompletion)
}

@Test
func sessionCoordinatorRequiresStableDoneWindowBeforeConfirmingCompletion() {
    var currentTime = Date(timeIntervalSince1970: 205)
    let coordinator = SessionCoordinator(
        now: { currentTime },
        completionIdleThreshold: 4,
        completionConfirmationThreshold: 2
    )
    let thread = ThreadSnapshot(
        threadID: "b",
        title: "New",
        source: "desktop",
        cwd: "/tmp/demo",
        updatedAt: Date(timeIntervalSince1970: 180),
        firstUserMessage: nil
    )
    let completion = CodexLogEvent(
        threadID: "b",
        kind: .responseCompleted,
        toolName: nil,
        summary: "Completed",
        timestamp: Date(timeIntervalSince1970: 200)
    )
    let resumedWork = CodexLogEvent(
        threadID: "b",
        kind: .toolUpdated,
        toolName: "exec_command",
        summary: "Still working",
        timestamp: Date(timeIntervalSince1970: 205)
    )

    coordinator.apply(threadSnapshots: [thread])
    coordinator.apply(logEvents: [completion])

    #expect(coordinator.currentSnapshot.statusText == "Running")
    #expect(!coordinator.currentSnapshot.shouldNotifyCompletion)

    coordinator.apply(logEvents: [resumedWork])

    currentTime = Date(timeIntervalSince1970: 208)
    #expect(coordinator.currentSnapshot.statusText == "Tool active")
    #expect(!coordinator.currentSnapshot.shouldNotifyCompletion)
}
