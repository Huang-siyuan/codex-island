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
    let url = router.sessionURL(threadID: "019d8ff6-5ac2-7a41-a931-a390c59c9eb0")

    #expect(url?.absoluteString == "codex://threads/019d8ff6-5ac2-7a41-a931-a390c59c9eb0")
}
