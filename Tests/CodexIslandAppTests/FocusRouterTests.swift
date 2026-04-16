import Testing
@testable import CodexIslandCore

@Test
func focusRouterBuildsKnownTargetsForCodexAndIdea() {
    let router = FocusRouter()

    #expect(router.target(for: .codex)?.bundleIdentifier == "com.openai.codex")
    #expect(router.target(for: .idea)?.bundleIdentifier == "com.jetbrains.intellij")
}

@Test
func focusRouterBuildsCodexThreadDeepLink() {
    let router = FocusRouter()
    let url = router.sessionURL(threadID: "Jackm")

    #expect(url?.absoluteString == "codex://threads/Jackm")
}
