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
func compactWidthTracksTheLongestStatusLabel() {
    #expect(
        IslandStatusPresentation.resolvedCompactWidth(forLabelWidths: [56, 49, 64]) == 109
    )
}
