import Foundation

public struct AppEnvironment: Sendable {
    public let codexHome: URL
    public let sessionIndexURL: URL
    public let stateStoreURL: URL
    public let logsStoreURL: URL
    public let claudeHome: URL
    public let claudeProjectsDirectory: URL
    public let codeBuddySupportDirectory: URL
    public let codeBuddySessionsStoreURL: URL
    public let codeBuddyTodosDirectory: URL
    public let codeBuddyGenieHistoryDirectory: URL
    public let codeBuddyCLIURL: URL

    public init(
        codexHome: URL,
        sessionIndexURL: URL,
        stateStoreURL: URL,
        logsStoreURL: URL,
        claudeHome: URL,
        claudeProjectsDirectory: URL,
        codeBuddySupportDirectory: URL,
        codeBuddySessionsStoreURL: URL,
        codeBuddyTodosDirectory: URL,
        codeBuddyGenieHistoryDirectory: URL,
        codeBuddyCLIURL: URL
    ) {
        self.codexHome = codexHome
        self.sessionIndexURL = sessionIndexURL
        self.stateStoreURL = stateStoreURL
        self.logsStoreURL = logsStoreURL
        self.claudeHome = claudeHome
        self.claudeProjectsDirectory = claudeProjectsDirectory
        self.codeBuddySupportDirectory = codeBuddySupportDirectory
        self.codeBuddySessionsStoreURL = codeBuddySessionsStoreURL
        self.codeBuddyTodosDirectory = codeBuddyTodosDirectory
        self.codeBuddyGenieHistoryDirectory = codeBuddyGenieHistoryDirectory
        self.codeBuddyCLIURL = codeBuddyCLIURL
    }

    public static let `default`: AppEnvironment = {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let codexHome = homeDirectory.appendingPathComponent(".codex")
        let claudeHome = homeDirectory.appendingPathComponent(".claude")
        let codeBuddySupportDirectory = homeDirectory
            .appendingPathComponent("Library/Application Support/CodeBuddy CN", isDirectory: true)
        return AppEnvironment(
            codexHome: codexHome,
            sessionIndexURL: codexHome.appendingPathComponent("session_index.jsonl"),
            stateStoreURL: codexHome.appendingPathComponent("state_5.sqlite"),
            logsStoreURL: codexHome.appendingPathComponent("logs_2.sqlite"),
            claudeHome: claudeHome,
            claudeProjectsDirectory: claudeHome.appendingPathComponent("projects", isDirectory: true),
            codeBuddySupportDirectory: codeBuddySupportDirectory,
            codeBuddySessionsStoreURL: codeBuddySupportDirectory.appendingPathComponent("codebuddy-sessions.vscdb"),
            codeBuddyTodosDirectory: codeBuddySupportDirectory
                .appendingPathComponent("User/globalStorage/tencent-cloud.coding-copilot/todos", isDirectory: true),
            codeBuddyGenieHistoryDirectory: codeBuddySupportDirectory
                .appendingPathComponent("User/globalStorage/tencent-cloud.coding-copilot/genie-history", isDirectory: true),
            codeBuddyCLIURL: URL(fileURLWithPath: "/Applications/CodeBuddy CN.app/Contents/Resources/app/bin/code")
        )
    }()
}
