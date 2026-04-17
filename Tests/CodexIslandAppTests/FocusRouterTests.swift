import Testing
@testable import CodexIslandCore

@Test
func focusRouterBuildsKnownTargetsForCodexCodeBuddyAndIdea() {
    let router = FocusRouter()

    #expect(router.target(for: .codex)?.bundleIdentifier == "com.openai.codex")
    #expect(router.target(for: .codeBuddy)?.bundleIdentifier == "com.tencent.codebuddycn")
    #expect(router.target(for: .idea)?.bundleIdentifier == "com.jetbrains.intellij")
}

@Test
func focusRouterBuildsCodexThreadDeepLink() {
    let router = FocusRouter()
    let url = router.sessionURL(threadID: "019d8ff6-5ac2-7a41-a931-a390c59c9eb0")

    #expect(url?.absoluteString == "codex://threads/019d8ff6-5ac2-7a41-a931-a390c59c9eb0")
}

@Test
func focusRouterBuildsClaudeResumeCommand() {
    let router = FocusRouter()
    let command = router.claudeResumeCommand(
        sessionID: "auth-refactor",
        workingDirectory: "/Users/demo/project"
    )

    #expect(command.contains("cd '/Users/demo/project'"))
    #expect(command.contains("claude -r 'auth-refactor'"))
}

@Test
func focusRouterBuildsCodeBuddyWorkspaceArguments() {
    let router = FocusRouter()

    #expect(router.codeBuddyCLIArguments(workingDirectory: "/Users/demo/project") == ["-r", "/Users/demo/project"])
}
