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

func screen(containing windowBounds: CGRect) -> NSScreen? {
    let screenFrames = NSScreen.screens.map(ScreenFrame.init)
    if let directMatch = screenFrames.first(where: { $0.quartzFrame.contains(windowBounds.center) }) {
        return directMatch.screen
    }

    return screenFrames.max(by: {
        $0.quartzFrame.intersectionArea(with: windowBounds) < $1.quartzFrame.intersectionArea(with: windowBounds)
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

guard let screen = screen(containing: islandWindow.bounds) else {
    fputs("Could not determine the island window's screen.\n", stderr)
    exit(1)
}

let desktopMaxY = NSScreen.screens.map(\.frame.maxY).max() ?? screen.frame.maxY
let expectedMinY = floor(desktopMaxY - screen.frame.maxY)
let heightTolerance: CGFloat = 2
let defaultWidth: CGFloat = 109
let menuBarThickness = max(
    screen.frame.maxY - screen.visibleFrame.maxY,
    screen.safeAreaInsets.top,
    NSStatusBar.system.thickness
)
let topAttachmentOverlap = ceil(min(6, max(4, ceil(menuBarThickness) * 0.18)))
let isBuiltInDisplay: Bool = {
    guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
        return false
    }

    return CGDisplayIsBuiltin(CGDirectDisplayID(truncating: screenNumber)) != 0
}()

let unavailableTopCenterWidth: CGFloat? = {
    guard #available(macOS 12.0, *),
          let leftArea = screen.auxiliaryTopLeftArea,
          let rightArea = screen.auxiliaryTopRightArea else {
        return nil
    }

    let normalizedLeft = leftArea.intersection(screen.frame)
    let normalizedRight = rightArea.intersection(screen.frame)
    let gapMinX = max(screen.frame.minX, normalizedLeft.maxX)
    let gapMaxX = min(screen.frame.maxX, normalizedRight.minX)
    let gapWidth = gapMaxX - gapMinX
    return gapWidth >= 60 ? gapWidth : nil
}()

let expectedWidth: CGFloat = {
    defaultWidth
}()

let extraVisibleReveal: CGFloat = {
    guard isBuiltInDisplay, unavailableTopCenterWidth != nil else {
        return 0
    }

    return 9
}()

guard abs(islandWindow.bounds.minY - expectedMinY) <= 8 else {
    fputs("Collapsed shell is not pinned to the screen top. expectedY=\(expectedMinY) actual=\(islandWindow.bounds.minY)\n", stderr)
    exit(1)
}

guard abs(islandWindow.bounds.width - expectedWidth) <= 2 else {
    fputs("Collapsed shell width is not adapted to the active screen. expected≈\(expectedWidth) actual=\(islandWindow.bounds.width)\n", stderr)
    exit(1)
}

guard abs(islandWindow.bounds.height - (menuBarThickness + extraVisibleReveal + topAttachmentOverlap)) <= heightTolerance else {
    fputs(
        "Collapsed shell height is not aligned to the notch reveal model. expected≈\(menuBarThickness + extraVisibleReveal + topAttachmentOverlap) actual=\(islandWindow.bounds.height)\n",
        stderr
    )
    exit(1)
}

print("Collapsed shell check passed.")
SWIFT
