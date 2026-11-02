import Testing
@testable import CodexIslandCore

@Test func smartSilenceOnlyMatchesFocusedCodexConversation() {
    let titles = [FocusSessionTitle(id: "a", title: "Task A"), FocusSessionTitle(id: "b", title: "Task B")]
    let focused = CodexFocusedWindow(title: "Task A", document: nil)
    #expect(SmartSilencePolicy.shouldSilence(provider: .codex, threadID: "a", focused: focused, titles: titles))
    #expect(!SmartSilencePolicy.shouldSilence(provider: .codex, threadID: "b", focused: focused, titles: titles))
    #expect(!SmartSilencePolicy.shouldSilence(provider: .claudeCode, threadID: "a", focused: focused, titles: titles))
    #expect(!SmartSilencePolicy.shouldSilence(provider: .codex, threadID: "a", focused: nil, titles: titles))
}

@Test func smartSilencePreservesAlertsForDuplicateOrUnknownTitles() {
    let duplicate = [FocusSessionTitle(id: "a", title: "Task"), FocusSessionTitle(id: "b", title: "Task")]
    let focused = CodexFocusedWindow(title: "Task", document: nil)
    #expect(!SmartSilencePolicy.shouldSilence(provider: .codex, threadID: "a", focused: focused, titles: duplicate))
    #expect(!SmartSilencePolicy.shouldSilence(provider: .codex, threadID: "a", focused: focused, titles: []))
    #expect(!SmartSilencePolicy.shouldSilence(provider: .codex, threadID: "a", focused: CodexFocusedWindow(title: "Tas", document: nil), titles: duplicate))
}

@Test func smartSilencePrefersExactDocumentThreadOverWindowTitle() {
    let focused = CodexFocusedWindow(title: "Task", document: "codex://threads/b")
    let titles = [FocusSessionTitle(id: "a", title: "Task")]
    #expect(!SmartSilencePolicy.shouldSilence(provider: .codex, threadID: "a", focused: focused, titles: titles))
    #expect(SmartSilencePolicy.shouldSilence(provider: .codex, threadID: "b", focused: focused, titles: titles))
}
