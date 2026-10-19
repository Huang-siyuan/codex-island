import Testing
@testable import CodexIslandCore

@Test
func compactStatusPresentationDoesNotShowDone() {
    #expect(IslandStatusPresentation.compactLabelText(for: "Done") == "Watching")
    #expect(IslandStatusPresentation.compactTone(for: "Done") == .passive)
}

@Test
func compactStatusPresentationKeepsActiveStates() {
    #expect(IslandStatusPresentation.compactLabelText(for: "Running") == "Running")
    #expect(IslandStatusPresentation.compactTone(for: "Running") == .running)
    #expect(IslandStatusPresentation.compactLabelText(for: "Tool active") == "Tool active")
    #expect(IslandStatusPresentation.compactTone(for: "Tool active") == .tool)
}

@Test
func interfaceLanguageTranslatesFixedStatusText() {
    let chinese = InterfaceLanguage.simplifiedChinese

    #expect(chinese.statusText(for: "Starting") == "启动中")
    #expect(chinese.statusText(for: "Running") == "运行中")
    #expect(chinese.statusText(for: "Tool active") == "工具执行中")
    #expect(chinese.statusText(for: "Done") == "已完成")
    #expect(chinese.compactStatusText(for: "Done") == "监看中")
    #expect(chinese.compactStatusText(for: "Tool active") == "工具中")
}

@Test
func interfaceLanguageLeavesUnknownDynamicStatusUntouched() {
    #expect(InterfaceLanguage.simplifiedChinese.statusText(for: "Claude Code") == "Claude Code")
}

@Test
func compactShellMetricsFavorANotchProfile() {
    let metrics = CompactIslandShellStyle.metrics(forHeight: 33)
    #expect(metrics.topCornerRadius == 8)
    #expect(metrics.bottomCornerRadius == 15)
    #expect(metrics.shoulderInset == 0)
    #expect(metrics.shoulderDepth == 10)
    #expect(metrics.topCornerRadius < metrics.bottomCornerRadius)
    #expect(metrics.shoulderInset == 0)
}

@Test
func compactWidthIncludesOnlyVisibleElements() {
    #expect(
        IslandStatusPresentation.resolvedCompactWidth(statusLabelWidth: 64, unreadLabelWidth: 60) == 182
    )
    #expect(IslandStatusPresentation.resolvedCompactWidth(statusLabelWidth: 64) == 109)
}

@Test
func unreadTextHidesUnknownAndZeroAndShowsExactLocalizedCount() {
    #expect(IslandStatusPresentation.unreadText(count: nil, language: .english) == nil)
    #expect(IslandStatusPresentation.unreadText(count: 0, language: .simplifiedChinese) == nil)
    #expect(IslandStatusPresentation.unreadText(count: 3, language: .simplifiedChinese) == "3 未读")
    #expect(IslandStatusPresentation.unreadText(count: 3, language: .english) == "3 unread")
    #expect(IslandStatusPresentation.unreadText(count: 21, language: .simplifiedChinese) == "21 未读")
    #expect(IslandStatusPresentation.unreadText(count: 1234, language: .english) == "1234 unread")
    #expect(IslandStatusPresentation.unreadAccessibilityLabel(count: 21, language: .english) == "21 unread Codex conversations")
    #expect(IslandStatusPresentation.unreadAccessibilityLabel(count: 21, language: .simplifiedChinese) == "21 个 Codex 会话未读")
    #expect(IslandStatusPresentation.unreadAccessibilityLabel(count: nil, language: .simplifiedChinese).contains("暂不可用"))
}

@Test
func compactWidthShrinksWhenUnreadClearsAndTracksActualDigitCount() {
    for language in [InterfaceLanguage.english, .simplifiedChinese] {
        let empty = IslandStatusPresentation.compactWidth(statusText: "Running", unreadCount: 0, language: language)
        let unknown = IslandStatusPresentation.compactWidth(statusText: "Running", unreadCount: nil, language: language)
        let single = IslandStatusPresentation.compactWidth(statusText: "Running", unreadCount: 3, language: language)
        let double = IslandStatusPresentation.compactWidth(statusText: "Running", unreadCount: 21, language: language)
        let long = IslandStatusPresentation.compactWidth(statusText: "Running", unreadCount: 123456, language: language)
        #expect(empty == unknown)
        #expect(empty < single)
        #expect(single < double)
        #expect(double < long)
        #expect(empty > IslandStatusPresentation.minimumCompactWidth)
    }
}

@Test
func compactWidthTracksCurrentStatusAndLanguage() {
    let chinese = IslandStatusPresentation.compactWidth(statusText: "Running", unreadCount: 0, language: .simplifiedChinese)
    let english = IslandStatusPresentation.compactWidth(statusText: "Running", unreadCount: 0, language: .english)
    let waiting = IslandStatusPresentation.compactWidth(statusText: "Waiting for input", unreadCount: 0, language: .english)
    #expect(chinese < english)
    #expect(english < waiting)
}
