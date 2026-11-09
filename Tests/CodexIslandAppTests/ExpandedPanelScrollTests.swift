@testable import CodexIslandApp
@testable import CodexIslandCore
import AppKit
import SwiftUI
import Testing

/// The expanded panel draws macOS overlay scrollers on its trailing edge. They must stay in the
/// shell's padding instead of covering the cards the page renders at full content width.
@MainActor
@Test func expandedPanelScrollerKeepsClearOfPageContent() throws {
    let panelWidth: CGFloat = 760
    let measuredContentWidth = WidthMeasurement()

    let page = VStack(spacing: 12) {
        ForEach(0..<10) { index in
            RoundedRectangle(cornerRadius: IslandLayout.cardRadius, style: .continuous)
                .fill(Color.white.opacity(0.1))
                .frame(height: 90)
                .overlay(Text("Card \(index)"))
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
        GeometryReader { proxy in
            Color.clear
                .onAppear { measuredContentWidth.value = proxy.size.width }
                .onChange(of: proxy.size.width) { _, width in measuredContentWidth.value = width }
        }
    }

    let host = NSHostingView(
        rootView: IslandPanelScrollView { page }
            .padding(.horizontal, IslandLayout.panelPadding)
            .frame(width: panelWidth)
            .frame(height: 420)
            .background(Color.black)
    )
    host.frame = NSRect(origin: .zero, size: host.fittingSize)

    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
    window.orderFrontRegardless()
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    host.layoutSubtreeIfNeeded()

    let scrollView = try #require(firstScrollView(in: host))
    let scroller = try #require(scrollView.verticalScroller)

    let contentWidth = try #require(measuredContentWidth.value)
    let contentRightEdge = IslandLayout.panelPadding + contentWidth
    let knobFrame = scroller.convert(scroller.rect(for: .knob), to: host)
    let scrollerFrame = scrollView.convert(scrollView.bounds, to: host)

    #expect(contentWidth == panelWidth - 2 * IslandLayout.panelPadding)
    // The scroll view reaches the shell edge so the scroller grows inside the padding.
    #expect(abs(scrollerFrame.maxX - panelWidth) < 1)
    #expect(knobFrame.minX > contentRightEdge)

    window.close()
}

@MainActor
private func firstScrollView(in view: NSView) -> NSScrollView? {
    if let scrollView = view as? NSScrollView {
        return scrollView
    }
    for subview in view.subviews {
        if let match = firstScrollView(in: subview) {
            return match
        }
    }
    return nil
}

@MainActor
private final class WidthMeasurement {
    var value: CGFloat?
}
