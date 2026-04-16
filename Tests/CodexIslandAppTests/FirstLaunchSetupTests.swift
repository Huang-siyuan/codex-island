import Foundation
import Testing
@testable import CodexIslandCore

@Test
func shellSnippetAddsAppSupportPath() {
    let setup = FirstLaunchSetup()
    let snippet = setup.shellSnippet(binDirectory: "/Users/test/Library/Application Support/CodexIsland/bin")

    #expect(snippet.contains("CodexIsland/bin"))
    #expect(snippet.contains("export PATH"))
    #expect(snippet.contains("codex-island"))
}

@Test
func notificationPolicySuppressesDuplicateCompletionEventsWithinCooldown() {
    let policy = NotificationPolicy(now: { Date(timeIntervalSince1970: 100) }, cooldown: 30)

    #expect(policy.shouldNotify(threadID: "thread-1", eventKind: .responseCompleted))
    #expect(!policy.shouldNotify(threadID: "thread-1", eventKind: .responseCompleted))
}
