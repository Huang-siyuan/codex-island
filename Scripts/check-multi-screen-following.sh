#!/bin/zsh
set -euo pipefail

# 使用独立临时应用的两个真实窗口验证已运行的 Island；结束后恢复之前的应用焦点。
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-island-screen-test.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
TEST_APP="$TEST_DIR/Screen Following Test.app"
mkdir -p "$TEST_APP/Contents/MacOS"
cat > "$TEST_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.codex.island.screen-test</string>
<key>CFBundleExecutable</key><string>ScreenTest</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
cat > "$TEST_DIR/main.swift" <<'SWIFT'
import AppKit
import CoreGraphics

@MainActor
final class ScreenTest: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private let previousApplication = NSRunningApplication(processIdentifier: pid_t(CommandLine.arguments[2]) ?? 0)
    private var report: [String] = []
    private let resultPath = CommandLine.arguments[1]

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            guard NSScreen.screens.count >= 2 else {
                finish("SKIP: This test requires two connected displays.")
                return
            }
            guard let island = NSRunningApplication.runningApplications(withBundleIdentifier: "local.codex.island").first else {
                finish("FAIL: Codex Island is not running.")
                return
            }
            let screens = Array(NSScreen.screens.prefix(2))
            for (index, screen) in screens.enumerated() {
                let size = index == 0 ? CGSize(width: 900, height: 600) : CGSize(width: 400, height: 300)
                let window = NSWindow(
                    contentRect: CGRect(
                        x: screen.frame.midX - size.width / 2,
                        y: screen.frame.midY - size.height / 2,
                        width: size.width,
                        height: size.height
                    ),
                    styleMask: [.titled, .closable],
                    backing: .buffered,
                    defer: false
                )
                window.title = "Codex Island 跨屏回归 \(index + 1)"
                window.isReleasedWhenClosed = false
                window.orderFront(nil)
                // NSWindow 初始化可能把屏幕外的 contentRect 约束到主屏；显示后显式设置桌面坐标。
                window.setFrameOrigin(CGPoint(
                    x: screen.frame.midX - size.width / 2,
                    y: screen.frame.midY - size.height / 2
                ))
                windows.append(window)
            }
            NSApp.activate(ignoringOtherApps: true)
            // PID 始终相同，只有窗口前后顺序变化；第二个窗口明显更小。
            for index in [0, 1, 0, 1] {
                windows[index].makeKeyAndOrderFront(nil)
                try? await Task.sleep(for: .milliseconds(900))
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier else {
                    finish("FAIL: Test interrupted by foreground application: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown").")
                    return
                }
                guard verifyIsland(island.processIdentifier, on: screens[index]) else {
                    finish("FAIL: Island did not follow window \(index + 1).")
                    return
                }
                report.append("PASS: same application, window \(index + 1), screen \(screens[index].localizedName)")
            }
            // 活跃窗口保持不变，跨屏移动也应更新刘海位置。
            windows[1].setFrameOrigin(CGPoint(x: screens[0].frame.midX - 200, y: screens[0].frame.midY - 150))
            try? await Task.sleep(for: .milliseconds(900))
            guard verifyIsland(island.processIdentifier, on: screens[0]) else {
                finish("FAIL: Island did not follow the moved window.")
                return
            }
            report.append("PASS: moved active window to the other screen")
            finish("PASS: Multi-screen following regression passed.")
        }
    }

    private func verifyIsland(_ pid: pid_t, on screen: NSScreen) -> Bool {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let window = info.first(where: { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid }),
              let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: dictionary) else {
            report.append("No visible Island window found")
            return false
        }
        let expectedTop = (NSScreen.screens.first?.frame.maxY ?? 0) - screen.frame.maxY
        let matches = abs(bounds.midX - screen.frame.midX) <= 2 && abs(bounds.minY - expectedTop) <= 10
        if !matches {
            report.append("Expected screen \(screen.frame), actual Island Quartz bounds \(bounds)")
            let testPID = ProcessInfo.processInfo.processIdentifier
            let testWindows = info.filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == testPID }
            for candidate in testWindows {
                report.append("Test window order: id=\(candidate[kCGWindowNumber as String] ?? "unknown"), bounds=\(candidate[kCGWindowBounds as String] ?? "unknown")")
            }
            report.append("Key window: \(NSApp.keyWindow?.windowNumber ?? -1)")
        }
        return matches
    }

    private func finish(_ result: String) {
        report.append(result)
        try? report.joined(separator: "\n").write(toFile: resultPath, atomically: true, encoding: .utf8)
        windows.forEach { $0.close() }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            previousApplication?.activate(options: [])
        }
        NSApp.terminate(nil)
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.regular)
let delegate = ScreenTest()
application.delegate = delegate
application.run()
SWIFT
swiftc -swift-version 6 "$TEST_DIR/main.swift" -o "$TEST_APP/Contents/MacOS/ScreenTest"
PREVIOUS_APP_PID="$(swift -e 'import AppKit; print(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)')"
open -n -W "$TEST_APP" --args "$TEST_DIR/result.txt" "$PREVIOUS_APP_PID"
cat "$TEST_DIR/result.txt"
rg -q '^PASS: Multi-screen following regression passed\.$' "$TEST_DIR/result.txt"
