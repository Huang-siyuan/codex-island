import AppKit
import CodexIslandCore
import OSLog
import SwiftUI

@MainActor
final class IslandPanelController {
    private let logger = Logger(subsystem: "CodexIsland", category: "Panel")
    private let screenLocator: ActiveScreenLocator
    private let viewModel: IslandViewModel
    private let topInset: CGFloat
    private let collapsedMinimumWidth: CGFloat
    private let minimumSize: CGSize
    private let panel: IslandWindow
    private let hostingView: TransparentHostingView<IslandRootView>
    private let topAttachmentState: TopAttachmentState

    init(viewModel: IslandViewModel, screenLocator: ActiveScreenLocator) {
        self.viewModel = viewModel
        self.screenLocator = screenLocator
        topInset = 0
        collapsedMinimumWidth = IslandStatusPresentation.preferredCompactWidth
        minimumSize = CGSize(width: collapsedMinimumWidth, height: 1)
        topAttachmentState = TopAttachmentState(
            value: MenuBarGeometry.resolvedCompactTopAttachmentOverlap(visibleHeight: 32)
        )
        if let initialScreen = screenLocator.activeScreen() ?? NSScreen.main ?? NSScreen.screens.first {
            let compactLayout = MenuBarGeometry.compactBarLayout(for: initialScreen, defaultWidth: collapsedMinimumWidth)
            _ = viewModel.updateCompactBarLayout(compactLayout)
            topAttachmentState.value = max(0, ceil(compactLayout.topAttachmentOverlap))
        }

        let initialFrame = CGRect(origin: .zero, size: CGSize(width: minimumSize.width, height: 44))
        let panel = IslandWindow(
            contentRect: initialFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false

        let measuredMinimumSize = minimumSize
        let measuredTopInset = topInset
        let topAttachmentState = self.topAttachmentState
        let hostingView = TransparentHostingView(
            rootView: IslandRootView(
                viewModel: viewModel,
                onMeasuredGeometryChange: { [weak panel, screenLocator] size, topAttachmentOverlap in
                    guard let panel else {
                        return
                    }

                    let preferredScreen = screenLocator.activeScreen()
                    let compactLayout = preferredScreen.map {
                        MenuBarGeometry.compactBarLayout(for: $0, defaultWidth: measuredMinimumSize.width)
                    }
                    if let compactLayout {
                        _ = viewModel.updateCompactBarLayout(compactLayout)
                    }
                    topAttachmentState.value = topAttachmentOverlap

                    Self.applyFrame(
                        to: panel,
                        targetSize: Self.normalizedSize(for: size, minimumSize: measuredMinimumSize),
                        on: preferredScreen,
                        topInset: measuredTopInset,
                        centerX: compactLayout?.centerX,
                        topAttachmentOverlap: topAttachmentOverlap
                    )
                }
            )
        )
        self.panel = panel
        self.hostingView = hostingView
        panel.contentView = hostingView
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        applyFrame()
    }

    func show() {
        logger.debug("show before frame=\(NSStringFromRect(self.panel.frame))")
        applyFrame()
        panel.orderFrontRegardless()
        logger.debug("show after frame=\(NSStringFromRect(self.panel.frame))")
    }

    func refreshPosition() {
        logger.debug("refreshPosition before frame=\(NSStringFromRect(self.panel.frame))")
        hostingView.layoutSubtreeIfNeeded()
        applyFrame()
        panel.orderFrontRegardless()
        logger.debug("refreshPosition after frame=\(NSStringFromRect(self.panel.frame))")
    }

    private func applyFrame() {
        let preferredScreen = screenLocator.activeScreen() ?? panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let preferredScreen else {
            logger.debug("applyFrame no screen, keeping frame=\(NSStringFromRect(self.panel.frame))")
            return
        }
        let compactLayout = MenuBarGeometry.compactBarLayout(for: preferredScreen, defaultWidth: collapsedMinimumWidth)
        if viewModel.updateCompactBarLayout(compactLayout) {
            hostingView.layoutSubtreeIfNeeded()
        }
        logger.debug("applyFrame screen=\(NSStringFromRect(preferredScreen.frame)) visible=\(NSStringFromRect(preferredScreen.visibleFrame))")
        Self.applyFrame(
            to: panel,
            targetSize: Self.normalizedSize(for: hostingView.fittingSize, minimumSize: minimumSize),
            on: preferredScreen,
            topInset: topInset,
            centerX: compactLayout.centerX,
            topAttachmentOverlap: topAttachmentState.value
        )
    }

    private static func applyFrame(
        to panel: IslandWindow,
        targetSize: CGSize,
        on preferredScreen: NSScreen?,
        topInset: CGFloat,
        centerX: CGFloat?,
        topAttachmentOverlap: CGFloat
    ) {
        guard let preferredScreen = preferredScreen ?? panel.screen ?? NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        let targetFrame = frame(
            for: targetSize,
            on: preferredScreen,
            topInset: topInset,
            centerX: centerX,
            topAttachmentOverlap: topAttachmentOverlap
        )
        guard panel.frame.integral != targetFrame.integral else {
            return
        }
        panel.setFrame(targetFrame, display: false)
    }

    private static func frame(
        for targetSize: CGSize,
        on screen: NSScreen,
        topInset: CGFloat,
        centerX: CGFloat?,
        topAttachmentOverlap: CGFloat
    ) -> CGRect {
        let displayFrame = screen.frame
        let resolvedCenterX = centerX ?? displayFrame.midX
        return CGRect(
            x: floor(resolvedCenterX - (targetSize.width / 2)),
            y: floor(displayFrame.maxY - topInset - targetSize.height + topAttachmentOverlap),
            width: targetSize.width,
            height: targetSize.height
        ).integral
    }

    private static func normalizedSize(for measuredSize: CGSize, minimumSize: CGSize) -> CGSize {
        CGSize(
            width: max(minimumSize.width, ceil(measuredSize.width)),
            height: max(minimumSize.height, ceil(measuredSize.height))
        )
    }
}

private final class TopAttachmentState {
    var value: CGFloat

    init(value: CGFloat) {
        self.value = value
    }
}

private final class IslandWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool {
        false
    }

    override var wantsDefaultClipping: Bool {
        false
    }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        layer?.masksToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        layer?.masksToBounds = false
        window?.backgroundColor = .clear
        window?.isOpaque = false
        window?.hasShadow = false
        window?.contentView?.wantsLayer = true
        window?.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        window?.contentView?.superview?.wantsLayer = true
        window?.contentView?.superview?.layer?.backgroundColor = NSColor.clear.cgColor
    }
}
