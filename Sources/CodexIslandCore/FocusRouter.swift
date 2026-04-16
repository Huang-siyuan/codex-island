import AppKit
import Foundation

public enum FocusTargetKind {
    case codex
    case idea
}

public struct FocusTarget: Equatable {
    public let bundleIdentifier: String

    public init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }
}

public struct FocusRouter {
    public init() {}

    public func target(for kind: FocusTargetKind) -> FocusTarget? {
        switch kind {
        case .codex:
            return FocusTarget(bundleIdentifier: "com.openai.codex")
        case .idea:
            return FocusTarget(bundleIdentifier: "com.jetbrains.intellij")
        }
    }

    @discardableResult
    public func activate(_ kind: FocusTargetKind) -> Bool {
        guard let target = target(for: kind) else {
            return false
        }

        if let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleIdentifier).first {
            return runningApp.activate(options: [.activateAllWindows])
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleIdentifier) else {
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in }
        return true
    }

    @discardableResult
    public func activateSession(threadID: String) -> Bool {
        guard let url = sessionURL(threadID: threadID) else {
            return activate(.codex)
        }

        if NSWorkspace.shared.open(url) {
            return true
        }

        return activate(.codex)
    }

    public func sessionURL(threadID: String) -> URL? {
        let encodedThreadID = threadID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? threadID
        return URL(string: "codex://threads/\(encodedThreadID)")
    }
}
