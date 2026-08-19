import Foundation
import SQLite3

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

        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open SQLite database"
            if let database {
                sqlite3_close(database)
            }
            throw SQLiteShellError.commandFailed(message)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 250)

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteShellError.commandFailed(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        var rows: [[String: Any]] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_DONE {
                break
            }
            guard stepResult == SQLITE_ROW else {
                throw SQLiteShellError.commandFailed(String(cString: sqlite3_errmsg(database)))
            }

            var row: [String: Any] = [:]
            for columnIndex in 0..<sqlite3_column_count(statement) {
                guard let rawName = sqlite3_column_name(statement, columnIndex) else {
                    continue
                }
                row[String(cString: rawName)] = value(from: statement, columnIndex: columnIndex)
            }
            rows.append(row)
        }

        guard !rows.isEmpty else {
            return []
        }
        let data = try JSONSerialization.data(withJSONObject: rows)
        return try JSONDecoder().decode([T].self, from: data)
    }

    private func value(from statement: OpaquePointer, columnIndex: Int32) -> Any {
        switch sqlite3_column_type(statement, columnIndex) {
        case SQLITE_INTEGER:
            return sqlite3_column_int64(statement, columnIndex)
        case SQLITE_FLOAT:
            return sqlite3_column_double(statement, columnIndex)
        case SQLITE_TEXT:
            guard let text = sqlite3_column_text(statement, columnIndex) else {
                return ""
            }
            return String(cString: text)
        case SQLITE_BLOB:
            guard let bytes = sqlite3_column_blob(statement, columnIndex) else {
                return Data().base64EncodedString()
            }
            let count = Int(sqlite3_column_bytes(statement, columnIndex))
            return Data(bytes: bytes, count: count).base64EncodedString()
        default:
            return NSNull()
        }
    }
}
