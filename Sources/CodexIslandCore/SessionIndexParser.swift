import Foundation

public struct SessionIndexParser {
    public init() {}

    public func parse(line: String) throws -> SessionIndexEntry {
        let payload = try JSONDecoder().decode(SessionIndexPayload.self, from: Data(line.utf8))
        let formatter = ISO8601DateFormatter()
        return SessionIndexEntry(
            threadID: payload.id,
            title: payload.threadName,
            updatedAt: formatter.date(from: payload.updatedAt) ?? .distantPast
        )
    }
}

private struct SessionIndexPayload: Decodable {
    let id: String
    let threadName: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case threadName = "thread_name"
        case updatedAt = "updated_at"
    }
}
