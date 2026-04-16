import Foundation

public struct LogsEventParser {
    public init() {}

    public func parse(row: LogRow) -> CodexLogEvent? {
        guard let threadID = row.threadID ?? extractThreadID(from: row.body) else {
            return nil
        }

        if let json = extractStructuredPayload(from: row.body),
           let event = parseStructuredEvent(json: json, threadID: threadID, timestamp: row.timestamp) {
            return event
        }

        if let kind = extractFallbackEventKind(from: row.body) {
            return CodexLogEvent(
                threadID: threadID,
                kind: kind,
                toolName: nil,
                summary: fallbackSummary(for: kind),
                timestamp: Date(timeIntervalSince1970: TimeInterval(row.timestamp))
            )
        }

        return nil
    }

    private func parseStructuredEvent(json: String, threadID: String, timestamp: Int64) -> CodexLogEvent? {
        let decoder = JSONDecoder()
        let eventTimestamp = Date(timeIntervalSince1970: TimeInterval(timestamp))
        guard let data = json.data(using: .utf8),
              let envelope = try? decoder.decode(GenericEnvelope.self, from: data) else {
            return nil
        }

        switch envelope.type {
        case "response.created":
            return CodexLogEvent(threadID: threadID, kind: .responseCreated, toolName: nil, summary: "Response created", timestamp: eventTimestamp)
        case "response.in_progress":
            return CodexLogEvent(threadID: threadID, kind: .responseInProgress, toolName: nil, summary: "Working", timestamp: eventTimestamp)
        case "response.completed":
            return CodexLogEvent(threadID: threadID, kind: .responseCompleted, toolName: nil, summary: "Completed", timestamp: eventTimestamp)
        case "response.function_call_arguments.delta", "response.function_call_arguments.done":
            guard let argsEnvelope = try? decoder.decode(FunctionArgsEnvelope.self, from: data) else {
                return nil
            }
            let command = decodeCommand(from: argsEnvelope.arguments) ?? "Tool call"
            return CodexLogEvent(
                threadID: threadID,
                kind: .toolUpdated,
                toolName: "exec_command",
                summary: summarize(command),
                timestamp: eventTimestamp
            )
        case "response.output_item.added", "response.output_item.done":
            guard let itemEnvelope = try? decoder.decode(OutputItemEnvelope.self, from: data) else {
                return nil
            }
            return parseOutputItemEvent(
                itemEnvelope,
                envelopeType: envelope.type,
                threadID: threadID,
                timestamp: eventTimestamp
            )
        default:
            return nil
        }
    }

    private func parseOutputItemEvent(
        _ envelope: OutputItemEnvelope,
        envelopeType: String,
        threadID: String,
        timestamp: Date
    ) -> CodexLogEvent? {
        switch envelope.item.type {
        case "function_call":
            let command = decodeCommand(from: envelope.item.arguments) ?? "Tool call"
            let kind: CodexLogEventKind = envelopeType == "response.output_item.done" ? .toolCompleted : .toolStarted
            return CodexLogEvent(
                threadID: threadID,
                kind: kind,
                toolName: envelope.item.name ?? "exec_command",
                summary: summarize(command),
                timestamp: timestamp
            )
        case "message":
            return CodexLogEvent(
                threadID: threadID,
                kind: .responseInProgress,
                toolName: nil,
                summary: envelope.item.phase == "commentary" ? "Assistant response" : "Response drafting",
                timestamp: timestamp
            )
        case "reasoning":
            return CodexLogEvent(
                threadID: threadID,
                kind: .responseInProgress,
                toolName: nil,
                summary: "Reasoning",
                timestamp: timestamp
            )
        default:
            return nil
        }
    }

    private func extractStructuredPayload(from body: String) -> String? {
        for marker in ["websocket event:", "Received message"] {
            guard let range = body.range(of: marker) else {
                continue
            }

            let suffix = String(body[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let json = extractJSONObjectCandidate(from: suffix) {
                return json
            }
        }

        if let typeRange = body.range(of: #"\{\"type\":"#, options: .regularExpression) {
            return String(body[typeRange.lowerBound...])
        }

        return nil
    }

    private func extractJSONObjectCandidate(from body: String) -> String? {
        guard let start = body.firstIndex(of: "{") else {
            return nil
        }
        return String(body[start...])
    }

    private func extractFallbackEventKind(from body: String) -> CodexLogEventKind? {
        if let eventName = extractFallbackEventName(from: body) {
            switch eventName {
            case "response.created":
                return .responseCreated
            case "response.in_progress":
                return .responseInProgress
            case "response.completed":
                return .responseCompleted
            default:
                break
            }
        }

        if body.contains("response.completed") {
            return .responseCompleted
        }
        if body.contains("response.in_progress") {
            return .responseInProgress
        }
        if body.contains("response.created") {
            return .responseCreated
        }

        return nil
    }

    private func extractFallbackEventName(from body: String) -> String? {
        for pattern in [#"unhandled responses event:\s*([A-Za-z0-9._-]+)"#, #"event\.kind=([A-Za-z0-9._-]+)"#] {
            guard let range = body.range(of: pattern, options: .regularExpression) else {
                continue
            }

            let matchedText = String(body[range])
            if let separator = matchedText.lastIndex(where: { $0 == " " || $0 == "=" }) {
                return String(matchedText[matchedText.index(after: separator)...])
            }
        }

        return nil
    }

    private func fallbackSummary(for kind: CodexLogEventKind) -> String {
        switch kind {
        case .responseCreated:
            return "Response created"
        case .responseInProgress:
            return "Working"
        case .responseCompleted:
            return "Completed"
        case .toolStarted:
            return "Tool call started"
        case .toolUpdated:
            return "Tool call updated"
        case .toolCompleted:
            return "Tool call completed"
        }
    }

    private func decodeCommand(from arguments: String?) -> String? {
        guard let arguments,
              let data = arguments.data(using: .utf8),
              let payload = try? JSONDecoder().decode(FunctionArguments.self, from: data) else {
            return nil
        }
        return payload.cmd
    }

    private func summarize(_ command: String) -> String {
        let trimmed = command.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 96 {
            return trimmed
        }
        return String(trimmed.prefix(93)) + "..."
    }

    private func extractThreadID(from body: String) -> String? {
        guard let range = body.range(of: #"thread_id=([A-Za-z0-9\-]+)"#, options: .regularExpression) else {
            return nil
        }
        let match = String(body[range])
        return match.replacingOccurrences(of: "thread_id=", with: "")
    }
}

private struct GenericEnvelope: Decodable {
    let type: String
}

private struct FunctionArgsEnvelope: Decodable {
    let type: String
    let arguments: String?
}

private struct OutputItemEnvelope: Decodable {
    let type: String
    let item: OutputItem
}

private struct OutputItem: Decodable {
    let type: String
    let status: String?
    let arguments: String?
    let name: String?
    let phase: String?
}

private struct FunctionArguments: Decodable {
    let cmd: String?
}
