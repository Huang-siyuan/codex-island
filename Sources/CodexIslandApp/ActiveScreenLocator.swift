import AppKit
import CoreGraphics

@MainActor
final class ActiveScreenLocator {
    private let islandPID = ProcessInfo.processInfo.processIdentifier
    private var lastExternalApplicationPID: pid_t?

    func noteActivatedApplication(_ application: NSRunningApplication?) {
        guard let application, application.processIdentifier != islandPID else {
            return
        }
        lastExternalApplicationPID = application.processIdentifier
    }

    func activeScreen() -> NSScreen? {
        if let screen = screenForApplicationWindow(frontmostExternalApplicationPID()) {
            return screen
        }

        if let screen = screenForApplicationWindow(lastExternalApplicationPID) {
            return screen
        }

        if let mainScreen = NSScreen.main {
            return mainScreen
        }

        let mouseLocation = NSEvent.mouseLocation
        if let hoveredScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return hoveredScreen
        }

        return NSScreen.screens.first
    }

    private func frontmostExternalApplicationPID() -> pid_t? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              frontmostApp.processIdentifier != islandPID else {
            return nil
        }
        return frontmostApp.processIdentifier
    }

    private func screenForApplicationWindow(_ processIdentifier: pid_t?) -> NSScreen? {
        guard let processIdentifier else {
            return nil
        }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]],
              let bounds = Self.frontmostWindowBounds(for: processIdentifier, in: windowInfo) else {
            return nil
        }
        return screen(for: bounds)
    }

    static func frontmostWindowBounds(for processIdentifier: pid_t, in windowInfo: [[String: Any]]) -> CGRect? {
        // optionOnScreenOnly 按前后顺序返回窗口；按面积排序会让另一屏的大窗口抢走焦点。
        windowInfo.lazy.compactMap(WindowCandidate.init).first {
            $0.ownerPID == processIdentifier &&
            $0.layer == 0 &&
            $0.alpha > 0.05 &&
            $0.bounds.width > 120 &&
            $0.bounds.height > 60
        }?.bounds
    }

    private func screen(for bounds: CGRect) -> NSScreen? {
        let screenFrames = NSScreen.screens.map(ScreenFrame.init)
        guard let index = Self.screenIndex(for: bounds, screenFrames: screenFrames.map(\.quartzFrame)) else {
            return nil
        }
        return screenFrames[index].screen
    }

    nonisolated static func quartzFrame(for screenFrame: CGRect, primaryScreenFrame: CGRect) -> CGRect {
        // Quartz 的原点在主屏左上角；上方副屏不能改变坐标转换基准。
        CGRect(
            x: screenFrame.minX,
            y: primaryScreenFrame.maxY - screenFrame.maxY,
            width: screenFrame.width,
            height: screenFrame.height
        )
    }

    static func screenIndex(for bounds: CGRect, screenFrames: [CGRect]) -> Int? {
        if let index = screenFrames.firstIndex(where: { $0.contains(bounds.center) }) {
            return index
        }
        return screenFrames.indices.filter {
            screenFrames[$0].intersectionArea(with: bounds) > 0
        }.max {
            screenFrames[$0].intersectionArea(with: bounds) < screenFrames[$1].intersectionArea(with: bounds)
        }
    }
}

private struct WindowCandidate {
    let ownerPID: pid_t
    let layer: Int
    let alpha: Double
    let bounds: CGRect

    init?(dictionary: [String: Any]) {
        guard let ownerPIDNumber = dictionary[kCGWindowOwnerPID as String] as? NSNumber,
              let layerNumber = dictionary[kCGWindowLayer as String] as? NSNumber,
              let alphaNumber = dictionary[kCGWindowAlpha as String] as? NSNumber,
              let boundsDictionary = dictionary[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else {
            return nil
        }

        self.ownerPID = pid_t(truncating: ownerPIDNumber)
        self.layer = layerNumber.intValue
        self.alpha = alphaNumber.doubleValue
        self.bounds = bounds
    }
}

private struct ScreenFrame {
    let screen: NSScreen
    let quartzFrame: CGRect

    init(screen: NSScreen) {
        self.screen = screen

        quartzFrame = ActiveScreenLocator.quartzFrame(
            for: screen.frame,
            primaryScreenFrame: NSScreen.screens.first?.frame ?? screen.frame
        )
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    func intersectionArea(with other: CGRect) -> CGFloat {
        let overlap = intersection(other)
        return overlap.isNull ? 0 : overlap.width * overlap.height
    }
}
