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

        let candidates = visibleWindowCandidates().filter {
            $0.ownerPID == processIdentifier
        }

        guard let window = candidates.max(by: { $0.area < $1.area }) else {
            return nil
        }

        return screen(for: window.bounds)
    }

    private func visibleWindowCandidates() -> [WindowCandidate] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return windowInfo.compactMap(WindowCandidate.init).filter {
            $0.layer == 0 &&
            $0.alpha > 0.05 &&
            $0.bounds.width > 120 &&
            $0.bounds.height > 60
        }
    }

    private func screen(for bounds: CGRect) -> NSScreen? {
        let screenFrames = NSScreen.screens.map(ScreenFrame.init)
        if let matchingScreen = screenFrames.first(where: { $0.quartzFrame.contains(bounds.center) }) {
            return matchingScreen.screen
        }

        return screenFrames
            .max(by: { $0.quartzFrame.intersectionArea(with: bounds) < $1.quartzFrame.intersectionArea(with: bounds) })?
            .screen
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

    var area: CGFloat {
        bounds.width * bounds.height
    }
}

private struct ScreenFrame {
    let screen: NSScreen
    let quartzFrame: CGRect

    init(screen: NSScreen) {
        self.screen = screen

        let desktopMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? screen.frame.maxY
        quartzFrame = CGRect(
            x: screen.frame.minX,
            y: desktopMaxY - screen.frame.maxY,
            width: screen.frame.width,
            height: screen.frame.height
        )
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    func intersectionArea(with other: CGRect) -> CGFloat {
        intersection(other).width * intersection(other).height
    }
}
