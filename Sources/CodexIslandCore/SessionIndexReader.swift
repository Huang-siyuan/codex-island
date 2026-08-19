import Foundation

public final class SessionIndexReader {
    private let parser = SessionIndexParser()
    private var cachedFileVersion: FileVersion?
    private var cachedEntries: [SessionIndexEntry] = []

    public init() {}

    public func readRecentSnapshots(from url: URL, limit: Int = 6) throws -> [ThreadSnapshot] {
        let entries = try readEntries(from: url)
            .sorted(by: { $0.updatedAt > $1.updatedAt })
            .prefix(limit)

        return entries.map {
            ThreadSnapshot(
                provider: .codex,
                threadID: $0.threadID,
                title: $0.title,
                source: "discovered",
                cwd: nil,
                updatedAt: $0.updatedAt,
                firstUserMessage: nil
            )
        }
    }

    public func readTitleOverrides(from url: URL, threadIDs: Set<String>) throws -> [String: String] {
        guard !threadIDs.isEmpty else {
            return [:]
        }

        return try readEntries(from: url).reduce(into: [:]) { partialResult, entry in
            guard threadIDs.contains(entry.threadID) else {
                return
            }
            let trimmedTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else {
                return
            }
            partialResult[entry.threadID] = trimmedTitle
        }
    }

    private func readEntries(from url: URL) throws -> [SessionIndexEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            cachedFileVersion = nil
            cachedEntries = []
            return []
        }

        let resourceValues = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let fileVersion = FileVersion(
            modificationDate: resourceValues.contentModificationDate,
            size: resourceValues.fileSize
        )
        if cachedFileVersion == fileVersion {
            return cachedEntries
        }

        let contents = try String(contentsOf: url, encoding: .utf8)
        let entries = try contents
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                try parser.parse(line: String(line))
            }
        cachedFileVersion = fileVersion
        cachedEntries = entries
        return entries
    }
}

private struct FileVersion: Equatable {
    let modificationDate: Date?
    let size: Int?
}
