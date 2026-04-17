import Foundation

enum SessionPreviewTextSanitizer {
    static func sanitize(_ text: String, previewLimit: Int = 160) -> String {
        var candidate = text
            .replacingOccurrences(
                of: #"\[([^\]]+)\]\([^)]+\)"#,
                with: "$1",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
                with: "***@***",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(
                of: #"(?<!\d)1\d{10}(?!\d)"#,
                with: "1**********",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?<![0-9A-Za-z])[0-9]{17}[0-9Xx](?![0-9A-Za-z])"#,
                with: "******************",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if candidate.count > previewLimit {
            candidate = String(candidate.prefix(previewLimit - 1)) + "…"
        }
        return candidate
    }
}

public struct SessionPreviewParser {
    private let previewLimit = 160

    public init() {}

    public func parse(row: LogRow) -> SessionMessagePreview? {
        guard let threadID = row.threadID ?? extractThreadID(from: row.body),
              let payload = extractStructuredPayload(from: row.body),
              let data = payload.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(GenericEnvelope.self, from: data) else {
            return nil
        }

        let timestamp = Date(timeIntervalSince1970: TimeInterval(row.timestamp))
        switch envelope.type {
        case "response.output_item.done":
            return parseAssistantPreview(from: data, threadID: threadID, timestamp: timestamp)
        case "response.create":
            return parseUserPreview(from: data, threadID: threadID, timestamp: timestamp)
        default:
            return nil
        }
    }

    private func parseAssistantPreview(from data: Data, threadID: String, timestamp: Date) -> SessionMessagePreview? {
        guard let envelope = try? JSONDecoder().decode(OutputItemEnvelope.self, from: data),
              envelope.item.type == "message",
              envelope.item.role == "assistant",
              envelope.item.status == "completed" else {
            return nil
        }

        let previews = envelope.item.content?
            .compactMap(\.text)
            .map { SessionPreviewTextSanitizer.sanitize($0, previewLimit: previewLimit) }
        guard let text = previews?.last(where: { !$0.isEmpty }) else {
            return nil
        }

        return SessionMessagePreview(
            provider: .codex,
            threadID: threadID,
            author: .assistant,
            text: text,
            timestamp: timestamp
        )
    }

    private func parseUserPreview(from data: Data, threadID: String, timestamp: Date) -> SessionMessagePreview? {
        guard let envelope = try? JSONDecoder().decode(ResponseCreateEnvelope.self, from: data),
              let input = envelope.input else {
            return nil
        }

        let text = input
            .filter { $0.role == "user" }
            .compactMap { item in
                let rawText = item.content?
                    .compactMap(\.text)
                    .joined(separator: "\n")
                    ?? item.text
                return rawText.map(sanitizeUserPreviewText)
            }
            .last(where: { !$0.isEmpty })

        guard let text else {
            return nil
        }

        return SessionMessagePreview(
            provider: .codex,
            threadID: threadID,
            author: .user,
            text: text,
            timestamp: timestamp
        )
    }

    private func sanitizeUserPreviewText(_ text: String) -> String {
        let normalized = text.replacingOccurrences(
            of: "\r\n",
            with: "\n"
        )

        for marker in ["## My request for Codex:", "My request for Codex:", "## My request:", "My request:"] {
            if let range = normalized.range(of: marker) {
                return SessionPreviewTextSanitizer.sanitize(
                    String(normalized[range.upperBound...]),
                    previewLimit: previewLimit
                )
            }
        }

        if let range = normalized.range(of: "</INSTRUCTIONS>") {
            let suffix = String(normalized[range.upperBound...])
            let cleaned = SessionPreviewTextSanitizer.sanitize(suffix, previewLimit: previewLimit)
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        let lines = normalized
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        if let lastLine = lines.last {
            return SessionPreviewTextSanitizer.sanitize(lastLine, previewLimit: previewLimit)
        }

        return SessionPreviewTextSanitizer.sanitize(normalized, previewLimit: previewLimit)
    }

    private func extractStructuredPayload(from body: String) -> String? {
        for marker in ["websocket event:", "Received message", "websocket request:"] {
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

private struct ResponseCreateEnvelope: Decodable {
    let type: String
    let input: [ResponseCreateInput]?
}

private struct ResponseCreateInput: Decodable {
    let role: String?
    let content: [ResponseCreateContent]?
    let text: String?
}

private struct ResponseCreateContent: Decodable {
    let type: String?
    let text: String?
}

private struct OutputItemEnvelope: Decodable {
    let type: String
    let item: PreviewOutputItem
}

private struct PreviewOutputItem: Decodable {
    let type: String
    let status: String?
    let role: String?
    let content: [PreviewOutputContent]?
}

private struct PreviewOutputContent: Decodable {
    let type: String
    let text: String?
}
