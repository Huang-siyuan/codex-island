import Foundation

public final class NotificationPolicy {
    private let now: () -> Date
    private let cooldown: TimeInterval
    private var lastSent: [String: Date] = [:]

    public init(now: @escaping () -> Date = Date.init, cooldown: TimeInterval = 20) {
        self.now = now
        self.cooldown = cooldown
    }

    public func shouldNotify(threadID: String, eventKind: CodexLogEventKind) -> Bool {
        let key = "\(threadID):\(eventKind.rawValue)"
        let current = now()
        if let previous = lastSent[key], current.timeIntervalSince(previous) < cooldown {
            return false
        }
        lastSent[key] = current
        return true
    }
}

public struct SetupResult: Sendable, Equatable {
    public let didPerform: Bool
    public let binDirectory: URL
    public let shellUpdated: Bool

    public init(didPerform: Bool, binDirectory: URL, shellUpdated: Bool) {
        self.didPerform = didPerform
        self.binDirectory = binDirectory
        self.shellUpdated = shellUpdated
    }
}

public struct FirstLaunchSetup {
    private let defaultsKey = "didPerformFirstLaunchSetup"

    public init() {}

    public func shellSnippet(binDirectory: String) -> String {
        """
        # >>> codex-island >>>
        if [ -d "\(binDirectory)" ]; then
          export PATH="\(binDirectory):$PATH"
        fi
        # codex-island wrapper available after first launch
        # <<< codex-island <<<
        """
    }

    public func performIfNeeded(fileManager: FileManager = .default, userDefaults: UserDefaults = .standard) throws -> SetupResult {
        let appSupportRoot = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexIsland", isDirectory: true)
        let binDirectory = appSupportRoot.appendingPathComponent("bin", isDirectory: true)

        guard !userDefaults.bool(forKey: defaultsKey) else {
            return SetupResult(didPerform: false, binDirectory: binDirectory, shellUpdated: false)
        }

        try fileManager.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        let wrapperURL = binDirectory.appendingPathComponent("codex")
        let codexPath = resolveCodexPath() ?? "/opt/homebrew/bin/codex"
        let wrapper = """
        #!/bin/zsh
        export CODEX_ISLAND_WRAPPED=1
        exec \(codexPath) "$@"
        """
        try wrapper.write(to: wrapperURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapperURL.path)

        let zshrcURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".zshrc")
        let snippet = shellSnippet(binDirectory: binDirectory.path)
        let shellUpdated = try appendSnippetIfNeeded(snippet, to: zshrcURL, fileManager: fileManager)

        userDefaults.set(true, forKey: defaultsKey)
        return SetupResult(didPerform: true, binDirectory: binDirectory, shellUpdated: shellUpdated)
    }

    private func appendSnippetIfNeeded(_ snippet: String, to url: URL, fileManager: FileManager) throws -> Bool {
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        guard !existing.contains("# >>> codex-island >>>") else {
            return false
        }

        let prefix = existing.isEmpty || existing.hasSuffix("\n") ? existing : existing + "\n"
        try (prefix + snippet + "\n").write(to: url, atomically: true, encoding: .utf8)
        return true
    }

    private func resolveCodexPath() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["codex"]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return nil
            }
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? nil : path
        } catch {
            return nil
        }
    }
}
