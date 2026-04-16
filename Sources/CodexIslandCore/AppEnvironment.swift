import Foundation

public struct AppEnvironment: Sendable {
    public let codexHome: URL
    public let sessionIndexURL: URL
    public let stateStoreURL: URL
    public let logsStoreURL: URL

    public init(codexHome: URL, sessionIndexURL: URL, stateStoreURL: URL, logsStoreURL: URL) {
        self.codexHome = codexHome
        self.sessionIndexURL = sessionIndexURL
        self.stateStoreURL = stateStoreURL
        self.logsStoreURL = logsStoreURL
    }

    public static let `default`: AppEnvironment = {
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        return AppEnvironment(
            codexHome: home,
            sessionIndexURL: home.appendingPathComponent("session_index.jsonl"),
            stateStoreURL: home.appendingPathComponent("state_5.sqlite"),
            logsStoreURL: home.appendingPathComponent("logs_2.sqlite")
        )
    }()
}
