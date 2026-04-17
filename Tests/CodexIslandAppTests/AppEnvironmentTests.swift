import Foundation
import Testing
@testable import CodexIslandCore

@Test
func defaultCodexPathsPointToHiddenCodexDirectory() {
    let environment = AppEnvironment.default

    #expect(environment.codexHome.path.hasSuffix("/.codex"))
    #expect(environment.sessionIndexURL.lastPathComponent == "session_index.jsonl")
    #expect(environment.stateStoreURL.lastPathComponent == "state_5.sqlite")
    #expect(environment.logsStoreURL.lastPathComponent == "logs_2.sqlite")
    #expect(environment.claudeHome.path.hasSuffix("/.claude"))
    #expect(environment.claudeProjectsDirectory.path.hasSuffix("/.claude/projects"))
    #expect(environment.codeBuddySessionsStoreURL.lastPathComponent == "codebuddy-sessions.vscdb")
    #expect(environment.codeBuddyTodosDirectory.path.contains("tencent-cloud.coding-copilot/todos"))
    #expect(environment.codeBuddyGenieHistoryDirectory.path.contains("tencent-cloud.coding-copilot/genie-history"))
    #expect(environment.codeBuddyCLIURL.path.hasSuffix("/CodeBuddy CN.app/Contents/Resources/app/bin/code"))
}
