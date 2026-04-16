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
}
