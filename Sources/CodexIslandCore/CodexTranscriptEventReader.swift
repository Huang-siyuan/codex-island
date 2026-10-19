import Foundation

/// Reads task lifecycle records without loading an entire conversation on every poll.
final class CodexTranscriptEventReader {
    private struct Cursor {
        let fileNumber: UInt64?
        let size: UInt64
        let modifiedAt: Date?
        let offset: UInt64
        let event: CodexLogEvent?
    }

    private struct Record: Decodable {
        let timestamp: String
        let type: String
        let payload: Payload

        struct Payload: Decodable {
            let type: String
        }
    }

    private let chunkSize = 64 * 1024
    private var cursors: [String: Cursor] = [:]
    private let decoder = JSONDecoder()
    private let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let dateFormatter = ISO8601DateFormatter()

    func latestEvent(at url: URL, threadID: String) throws -> CodexLogEvent? {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        let modifiedAt = attributes[.modificationDate] as? Date
        let previous = cursors[url.path]
        if let previous, previous.fileNumber == fileNumber,
           previous.size == size, previous.modifiedAt == modifiedAt {
            return previous.event
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let offset: UInt64
        let event: CodexLogEvent?
        if let previous, previous.fileNumber == fileNumber, size > previous.size {
            (offset, event) = try readAppendedRecords(
                handle: handle, from: previous.offset, through: size,
                threadID: threadID, previousEvent: previous.event
            )
        } else {
            // On startup or replacement, find only the last lifecycle record by reading
            // backwards. Large tool outputs and incomplete final lines are skipped safely.
            (offset, event) = try readLatestRecord(handle: handle, size: size, threadID: threadID)
        }
        cursors[url.path] = Cursor(
            fileNumber: fileNumber, size: size, modifiedAt: modifiedAt, offset: offset, event: event
        )
        return event
    }

    private func readLatestRecord(
        handle: FileHandle, size: UInt64, threadID: String
    ) throws -> (UInt64, CodexLogEvent?) {
        var position = size
        var buffer = Data()
        var completeOffset: UInt64?
        while position > 0 {
            let count = Int(min(UInt64(chunkSize), position))
            position -= UInt64(count)
            try handle.seek(toOffset: position)
            let chunk = try handle.read(upToCount: count) ?? Data()
            buffer = chunk + buffer
            if completeOffset == nil, let newline = buffer.lastIndex(of: 0x0A) {
                completeOffset = position + UInt64(newline) + 1
                buffer = Data(buffer[..<newline])
            }
            guard let lastCompleteOffset = completeOffset else {
                continue
            }
            while let newline = buffer.lastIndex(of: 0x0A) {
                let line = Data(buffer[(newline + 1)...])
                buffer = Data(buffer[..<newline])
                if let event = parse(line, threadID: threadID) {
                    return (lastCompleteOffset, event)
                }
            }
        }
        return (completeOffset ?? 0, completeOffset == nil ? nil : parse(buffer, threadID: threadID))
    }

    private func readAppendedRecords(
        handle: FileHandle, from offset: UInt64, through size: UInt64,
        threadID: String, previousEvent: CodexLogEvent?
    ) throws -> (UInt64, CodexLogEvent?) {
        try handle.seek(toOffset: offset)
        var position = offset
        var completeOffset = offset
        var buffer = Data()
        var event = previousEvent
        while position < size {
            let count = Int(min(UInt64(chunkSize), size - position))
            let chunk = try handle.read(upToCount: count) ?? Data()
            guard !chunk.isEmpty else {
                break
            }
            position += UInt64(chunk.count)
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                completeOffset += UInt64(newline + 1)
                buffer = Data(buffer[(newline + 1)...])
                if let parsed = parse(line, threadID: threadID) {
                    event = parsed
                }
            }
        }
        // Retain the start of an incomplete line so it can be retried on the next append.
        return (completeOffset, event)
    }

    private func parse(_ line: Data, threadID: String) -> CodexLogEvent? {
        guard let record = try? decoder.decode(Record.self, from: line),
              record.type == "event_msg",
              let timestamp = fractionalDateFormatter.date(from: record.timestamp)
                ?? dateFormatter.date(from: record.timestamp) else {
            return nil
        }
        let kind: CodexLogEventKind
        let summary: String
        switch record.payload.type {
        case "task_started":
            kind = .responseCreated
            summary = "Task started"
        case "task_complete":
            kind = .responseCompleted
            summary = "Completed"
        case "turn_aborted":
            kind = .responseInterrupted
            summary = "Stopped"
        default:
            return nil
        }
        return CodexLogEvent(
            threadID: threadID, kind: kind, toolName: nil, summary: summary, timestamp: timestamp
        )
    }
}
