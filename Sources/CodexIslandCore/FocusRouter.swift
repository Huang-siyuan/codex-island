import AppKit
import Foundation

public enum FocusTargetKind {
    case codex
    case codeBuddy
    case idea
}

public struct FocusTarget: Equatable {
    public let bundleIdentifier: String

    public init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }
}

public struct FocusRouter {
    private let environment: AppEnvironment

    public init(environment: AppEnvironment = .default) {
        self.environment = environment
    }

    public func target(for kind: FocusTargetKind) -> FocusTarget? {
        switch kind {
        case .codex:
            return FocusTarget(bundleIdentifier: "com.openai.codex")
        case .codeBuddy:
            return FocusTarget(bundleIdentifier: "com.tencent.codebuddycn")
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
        activateSession(.codex(threadID: threadID))
    }

    @discardableResult
    public func activateSession(_ navigationTarget: SessionNavigationTarget) -> Bool {
        switch navigationTarget {
        case .codex(let threadID):
            guard let url = sessionURL(threadID: threadID) else {
                return activate(.codex)
            }
            if NSWorkspace.shared.open(url) {
                return true
            }
            return activate(.codex)
        case .claudeCode(let sessionID, let workingDirectory):
            return launchClaudeResume(sessionID: sessionID, workingDirectory: workingDirectory)
        case .codeBuddy(_, let workingDirectory):
            if let workingDirectory, launchCodeBuddy(workingDirectory: workingDirectory) {
                return true
            }
            return activate(.codeBuddy)
        }
    }

    public func sessionURL(threadID: String) -> URL? {
        let encodedThreadID = threadID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? threadID
        return URL(string: "codex://threads/\(encodedThreadID)")
    }

    public func claudeResumeCommand(sessionID: String, workingDirectory: String?) -> String {
        let resumeCommand = "claude -r \(shellQuote(sessionID))"
        guard let workingDirectory, !workingDirectory.isEmpty else {
            return resumeCommand
        }
        return "cd \(shellQuote(workingDirectory)) && \(resumeCommand)"
    }

    public func codeBuddyCLIArguments(workingDirectory: String) -> [String] {
        ["-r", workingDirectory]
    }

    private func launchClaudeResume(sessionID: String, workingDirectory: String?) -> Bool {
        let command = claudeResumeCommand(sessionID: sessionID, workingDirectory: workingDirectory)
        let script = """
        tell application "Terminal"
            activate
            do script "\(escapedForAppleScript(command))"
        end tell
        """
        return runAppleScript(script)
    }

    private func launchCodeBuddy(workingDirectory: String) -> Bool {
        guard FileManager.default.fileExists(atPath: environment.codeBuddyCLIURL.path) else {
            return false
        }

        let process = Process()
        process.executableURL = environment.codeBuddyCLIURL
        process.arguments = codeBuddyCLIArguments(workingDirectory: workingDirectory)
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    private func runAppleScript(_ script: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func shellQuote(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    private func escapedForAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
