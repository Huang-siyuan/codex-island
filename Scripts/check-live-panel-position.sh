#!/bin/zsh
set -euo pipefail

swift - <<'SWIFT'
import AppKit
import CoreGraphics
import Foundation

struct WindowCandidate {
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

        ownerPID = pid_t(truncating: ownerPIDNumber)
        layer = layerNumber.intValue
        alpha = alphaNumber.doubleValue
        self.bounds = bounds
    }

    var area: CGFloat {
        bounds.width * bounds.height
    }
}

struct ScreenFrame {
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

extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    func intersectionArea(with other: CGRect) -> CGFloat {
        intersection(other).width * intersection(other).height
    }
}

func activeScreen() -> NSScreen? {
    let islandPID = NSRunningApplication.runningApplications(withBundleIdentifier: "local.codex.island").first?.processIdentifier

    guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
        return NSScreen.main ?? NSScreen.screens.first
    }

    let candidates = windowInfo.compactMap(WindowCandidate.init).filter {
        $0.layer == 0 &&
        $0.alpha > 0.05 &&
        $0.bounds.width > 120 &&
        $0.bounds.height > 60
    }

    if let frontmostApp = NSWorkspace.shared.frontmostApplication,
       frontmostApp.processIdentifier != islandPID {
        let frontmostWindows = candidates.filter { $0.ownerPID == frontmostApp.processIdentifier }
        if let window = frontmostWindows.max(by: { $0.area < $1.area }) {
            let screenFrames = NSScreen.screens.map(ScreenFrame.init)
            if let directMatch = screenFrames.first(where: { $0.quartzFrame.contains(window.bounds.center) }) {
                return directMatch.screen
            }

            return screenFrames.max(by: {
                $0.quartzFrame.intersectionArea(with: window.bounds) < $1.quartzFrame.intersectionArea(with: window.bounds)
            })?.screen
        }
    }

    guard let window = candidates.first(where: { $0.ownerPID != islandPID }) else {
        return NSScreen.main ?? NSScreen.screens.first
    }

    let screenFrames = NSScreen.screens.map(ScreenFrame.init)
    if let directMatch = screenFrames.first(where: { $0.quartzFrame.contains(window.bounds.center) }) {
        return directMatch.screen
    }

    return screenFrames.max(by: {
        $0.quartzFrame.intersectionArea(with: window.bounds) < $1.quartzFrame.intersectionArea(with: window.bounds)
    })?.screen
}

guard let islandApp = NSRunningApplication.runningApplications(withBundleIdentifier: "local.codex.island").first else {
    fputs("Codex Island is not running.\n", stderr)
    exit(1)
}

guard let windowInfo = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]],
      let islandWindow = windowInfo.compactMap(WindowCandidate.init).first(where: { $0.ownerPID == islandApp.processIdentifier }) else {
    fputs("Could not find the Codex Island window.\n", stderr)
    exit(1)
}

guard let screen = activeScreen() else {
    fputs("Could not determine the active screen.\n", stderr)
    exit(1)
}

let desktopMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? screen.frame.maxY
let menuBarThickness = max(
    screen.frame.maxY - screen.visibleFrame.maxY,
    screen.safeAreaInsets.top,
    NSStatusBar.system.thickness
)
let topAttachmentOverlap = ceil(min(6, max(4, ceil(menuBarThickness) * 0.18)))
let expectedCenterX: CGFloat = {
    guard #available(macOS 12.0, *),
          let leftArea = screen.auxiliaryTopLeftArea,
          let rightArea = screen.auxiliaryTopRightArea else {
        return screen.frame.midX
    }

    let normalizedLeft = leftArea.intersection(screen.frame)
    let normalizedRight = rightArea.intersection(screen.frame)
    let gapMinX = max(screen.frame.minX, normalizedLeft.maxX)
    let gapMaxX = min(screen.frame.maxX, normalizedRight.minX)
    let gapWidth = gapMaxX - gapMinX
    return gapWidth >= 60 ? (gapMinX + (gapWidth / 2)) : screen.frame.midX
}()
let expectedQuartzFrame = CGRect(
    x: floor(expectedCenterX - (islandWindow.bounds.width / 2)),
    y: floor(desktopMaxY - screen.frame.maxY - topAttachmentOverlap),
    width: islandWindow.bounds.width,
    height: islandWindow.bounds.height
).integral

let frameMatches = abs(islandWindow.bounds.minX - expectedQuartzFrame.minX) <= 2 &&
    abs(islandWindow.bounds.minY - expectedQuartzFrame.minY) <= 2

guard frameMatches else {
    fputs(
        "Island window is not pinned to the active screen top. expected=\(expectedQuartzFrame) actual=\(islandWindow.bounds)\n",
        stderr
    )
    exit(1)
}

print("Live panel position check passed.")
SWIFT
