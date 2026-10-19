import Foundation

/// Reads task lifecycle records without loading an entire conversation on every poll.
final class CodexTranscriptEventReader {
    private struct Cursor {
        let fileNumber: UInt64?
        let size: UInt64
        let modifiedAt: Date?
        let offset: UInt64
        let state: TranscriptState
    }

    private struct Record: Decodable {
        let timestamp: String
        let type: String
        let payload: Payload

        struct Payload: Decodable {
            let type: String
            let name: String?
            let call_id: String?
            let output: String?
        }
    }

    private struct InputRequest {
        let event: CodexLogEvent
        let asynchronous: Bool
    }

    private struct TranscriptState {
        var lifecycle: CodexLogEvent?
        var requests: [String: InputRequest] = [:]

        var latestEvent: CodexLogEvent? {
            requests.values.map(\.event).max { $0.timestamp < $1.timestamp } ?? lifecycle
        }

        mutating func apply(_ update: Update) {
            switch update {
            case .lifecycle(let event):
                lifecycle = event
                requests.removeAll()
            case .request(let id, let request):
                requests[id] = request
            case .output(let id, let accepted, let event):
                guard let request = requests[id] else {
                    return
                }
                // Async tools return an acknowledgement immediately, before the user answers.
                if !request.asynchronous || !accepted {
                    requests.removeValue(forKey: id)
                    lifecycle = event
                }
            case .userReply(let event):
                requests.removeAll()
                lifecycle = event
            }
        }
    }

    private enum Update {
        case lifecycle(CodexLogEvent)
        case request(String, InputRequest)
        case output(String, Bool, CodexLogEvent)
        case userReply(CodexLogEvent)
    }

    private struct InputAcknowledgement: Decodable {
        let accepted: Bool
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
            return previous.state.latestEvent
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let offset: UInt64
        let state: TranscriptState
        if let previous, previous.fileNumber == fileNumber, size > previous.size {
            (offset, state) = try readAppendedRecords(
                handle: handle, from: previous.offset, through: size,
                threadID: threadID, previousState: previous.state
            )
        } else {
            // Reconstruct pending requests since the latest task boundary on startup or
            // replacement. Subsequent polls only read appended complete records.
            (offset, state) = try readLatestRecord(handle: handle, size: size, threadID: threadID)
        }
        cursors[url.path] = Cursor(
            fileNumber: fileNumber, size: size, modifiedAt: modifiedAt, offset: offset, state: state
        )
        return state.latestEvent
    }

    private func readLatestRecord(
        handle: FileHandle, size: UInt64, threadID: String
    ) throws -> (UInt64, TranscriptState) {
        var position = size
        var buffer = Data()
        var completeOffset: UInt64?
        var updates: [Update] = []
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
                if let update = parse(line, threadID: threadID) {
                    updates.append(update)
                    if case .lifecycle = update {
                        return (lastCompleteOffset, replay(updates))
                    }
                }
            }
        }
        if completeOffset != nil, let update = parse(buffer, threadID: threadID) {
            updates.append(update)
        }
        return (completeOffset ?? 0, replay(updates))
    }

    private func readAppendedRecords(
        handle: FileHandle, from offset: UInt64, through size: UInt64,
        threadID: String, previousState: TranscriptState
    ) throws -> (UInt64, TranscriptState) {
        try handle.seek(toOffset: offset)
        var position = offset
        var completeOffset = offset
        var buffer = Data()
        var state = previousState
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
                    state.apply(parsed)
                }
            }
        }
        // Retain the start of an incomplete line so it can be retried on the next append.
        return (completeOffset, state)
    }

    private func replay(_ reversedUpdates: [Update]) -> TranscriptState {
        var state = TranscriptState()
        for update in reversedUpdates.reversed() {
            state.apply(update)
        }
        return state
    }

    private func parse(_ line: Data, threadID: String) -> Update? {
        guard let record = try? decoder.decode(Record.self, from: line),
              let timestamp = fractionalDateFormatter.date(from: record.timestamp)
                ?? dateFormatter.date(from: record.timestamp) else {
            return nil
        }
        if record.type == "response_item" {
            let payload = record.payload
            if payload.type == "function_call", let name = payload.name,
               let id = payload.call_id,
               ["request_user_input", "functions.request_user_input",
                "request_user_input_async", "functions.request_user_input_async"].contains(name) {
                let event = CodexLogEvent(
                    threadID: threadID, kind: .userInputRequested, toolName: name,
                    summary: "Waiting for input", timestamp: timestamp
                )
                return .request(id, InputRequest(event: event, asynchronous: name.hasSuffix("_async")))
            }
            if payload.type == "function_call_output", let id = payload.call_id {
                let accepted = payload.output.flatMap { $0.data(using: .utf8) }
                    .flatMap { try? decoder.decode(InputAcknowledgement.self, from: $0) }?.accepted ?? false
                return .output(id, accepted, CodexLogEvent(
                    threadID: threadID, kind: .responseInProgress, toolName: nil,
                    summary: "Working", timestamp: timestamp
                ))
            }
            return nil
        }
        guard record.type == "event_msg" else {
            return nil
        }
        if record.payload.type == "user_message" {
            return .userReply(CodexLogEvent(
                threadID: threadID, kind: .responseInProgress, toolName: nil,
                summary: "Working", timestamp: timestamp
            ))
        }
        let kind: CodexLogEventKind
        let summary: String
        switch record.payload.type {
        case "task_started":
            kind = .responseCreated
            summary = "Task started"
        case "task_complete":
            kind = .taskCompleted
            summary = "Completed"
        case "turn_aborted":
            kind = .responseInterrupted
            summary = "Stopped"
        default:
            return nil
        }
        return .lifecycle(CodexLogEvent(
            threadID: threadID, kind: kind, toolName: nil, summary: summary, timestamp: timestamp
        ))
    }
}
