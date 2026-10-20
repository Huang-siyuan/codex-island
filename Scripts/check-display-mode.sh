#!/bin/zsh
set -euo pipefail

# 只读检查已安装应用的模式与真实可见面板；不改设置、不切换前台应用。
swift - <<'SWIFT'
import AppKit
import CoreGraphics

func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "local.codex.island").first,
      let info = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
    fail("Codex Island must be running in an unlocked desktop session.")
}
let frames = info.filter {
    ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == app.processIdentifier &&
    ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == Int(NSWindow.Level.statusBar.rawValue)
}.compactMap { window -> CGRect? in
    guard let bounds = window[kCGWindowBounds as String] as? NSDictionary else { return nil }
    return CGRect(dictionaryRepresentation: bounds)
}
let mode = UserDefaults(suiteName: "local.codex.island")?.string(forKey: "islandDisplayMode") ?? "followFocus"
let screens = NSScreen.screens
let expectedCount = mode == "everyScreen" ? screens.count : 1
guard frames.count == expectedCount else {
    fail("mode=\(mode), expected \(expectedCount) panels, found \(frames.count): \(frames)")
}
let primaryTop = screens.first?.frame.maxY ?? 0
if mode == "everyScreen" {
    for screen in screens {
        let expectedTop = primaryTop - screen.frame.maxY
        let matches = frames.filter {
            abs($0.midX - screen.frame.midX) <= 2 && abs($0.minY - expectedTop) <= 10
        }
        guard matches.count == 1 else {
            fail("Expected exactly one top-centered panel on \(screen.localizedName): \(frames)")
        }
        print("PASS: \(screen.localizedName), \(matches[0])")
    }
}
print("PASS: display mode \(mode), \(frames.count) visible panel(s)")
SWIFT
