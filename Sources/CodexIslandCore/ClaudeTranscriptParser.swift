import Foundation

public final class ClaudeTranscriptParser {
    private let previewLimit = 160

    public init() {}

    public func parse(
        sessionID: String,
        transcript: String,
        updatedAt: Date,
        workingDirectory: String? = nil
    ) -> ProviderSessionMaterial? {
        var title: String?
        var cwd = workingDirectory
        var userText: String?
        var assistantText: String?

        for line in transcript.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if title == nil {
                title = firstString(in: object, keys: ["sessionName", "title", "name"])
            }
            if cwd == nil {
                cwd = firstString(in: object, keys: ["cwd", "workingDirectory", "projectDir", "path"])
            }

            if let message = object["message"] as? [String: Any] {
                let role = (message["role"] as? String)?.lowercased()
                let text = extractText(from: message["content"]) ?? firstString(in: message, keys: ["text"])
                let sanitized = text.map { SessionPreviewTextSanitizer.sanitize($0, previewLimit: previewLimit) }

                switch role {
                case "user":
                    if let sanitized, !sanitized.isEmpty {
                        userText = sanitized
                    }
                case "assistant":
                    if let sanitized, !sanitized.isEmpty {
                        assistantText = sanitized
                    }
                default:
                    break
                }
            }
        }

        let resolvedTitle = SessionPreviewTextSanitizer.sanitize(
            title ?? userText ?? sessionID,
            previewLimit: 90
        )
        let snapshot = ThreadSnapshot(
            provider: .claudeCode,
            threadID: sessionID,
            title: resolvedTitle.isEmpty ? sessionID : resolvedTitle,
            source: "claude",
            cwd: cwd,
            updatedAt: updatedAt,
            firstUserMessage: userText
        )
        let userPreview = userText.map {
            SessionMessagePreview(
                provider: .claudeCode,
                threadID: sessionID,
                author: .user,
                text: $0,
                timestamp: updatedAt
            )
        }
        let assistantPreview = assistantText.map {
            SessionMessagePreview(
                provider: .claudeCode,
                threadID: sessionID,
                author: .assistant,
                text: $0,
                timestamp: updatedAt
            )
        }
        let event: CodexLogEvent? = {
            if let assistantText {
                return CodexLogEvent(
                    provider: .claudeCode,
                    threadID: sessionID,
                    kind: .responseCompleted,
                    toolName: nil,
                    summary: assistantText,
                    timestamp: updatedAt
                )
            }
            if let userText {
                return CodexLogEvent(
                    provider: .claudeCode,
                    threadID: sessionID,
                    kind: .responseCreated,
                    toolName: nil,
                    summary: userText,
                    timestamp: updatedAt
                )
            }
            return nil
        }()

        guard title != nil || userPreview != nil || assistantPreview != nil else {
            return nil
        }

        return ProviderSessionMaterial(
            threadSnapshot: snapshot,
            userPreview: userPreview,
            assistantPreview: assistantPreview,
            event: event
        )
    }

    private func firstString(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private func extractText(from value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let dictionary = value as? [String: Any] {
            if let text = dictionary["text"] as? String {
                return text
            }
            for nestedValue in dictionary.values {
                if let nestedText = extractText(from: nestedValue) {
                    return nestedText
                }
            }
            return nil
        }
        if let array = value as? [Any] {
            let texts = array.compactMap { extractText(from: $0) }
            guard !texts.isEmpty else {
                return nil
            }
            return texts.joined(separator: "\n")
        }
        return nil
    }
}
