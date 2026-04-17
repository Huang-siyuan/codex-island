import Foundation

public enum SQLiteShellError: Error, LocalizedError {
    case commandFailed(String)
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let message), .invalidJSON(let message):
            return message
        }
    }
}

public struct SQLiteShell {
    public init() {}

    public func query<T: Decodable>(databaseURL: URL, query: String) throws -> [T] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return []
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-json", databaseURL.path, query]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let message = String(decoding: err, as: UTF8.self)
            throw SQLiteShellError.commandFailed(message)
        }

        let trimmed = String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw SQLiteShellError.invalidJSON("Could not encode sqlite output")
        }
        return try JSONDecoder().decode([T].self, from: data)
    }
}
