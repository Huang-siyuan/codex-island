import Foundation

struct DeepSeekEmpty: Codable, Sendable {}
struct DeepSeekListArguments: Encodable, Sendable { let _request = DeepSeekEmpty() }
struct DeepSeekRequestArguments<Request: Encodable & Sendable>: Encodable, Sendable {
    let request: Request
}
struct DeepSeekSessionRequest: Encodable, Sendable { let sessionId: String }
struct DeepSeekHistoryRequest: Encodable, Sendable {
    let address: Address
    let maxMessages = 3
    struct Address: Encodable, Sendable {
        let kind = "session"
        let sessionId: String
    }
}
struct DeepSeekSessionList: Decodable, Sendable { let items: [DeepSeekSession] }
struct DeepSeekSession: Decodable, Sendable {
    let sessionId: String
    let updatedAt: Double
    let agentAvailable: Bool
    let running: Bool
    let blank: Bool
    let cwd: String?
    let projections: DeepSeekProjection?
}
struct DeepSeekProjection: Decodable, Sendable {
    let kind: String
    let asOfSeq: Int?
    let values: Values
    struct Values: Decodable, Sendable {
        let title: String?
        let workingDirectory: String?
        let turnOutline: [Turn]?
        let tokenUsage: DeepSeekTokenUsage?
        let contextPressure: ContextPressure?
        let userQuestions: Questions?
        struct Turn: Decodable, Sendable {
            let prompt: String
            let response: String
        }
        struct ContextPressure: Decodable, Sendable {
            let projectedTokens: Int?
            let contextWindow: Int?
        }
        struct Questions: Decodable, Sendable { let active: [DeepSeekQuestionCall] }
    }
}
struct DeepSeekQuestionCall: Decodable, Sendable {
    let callId: String
    let state: String
    let questions: [Question]
    struct Question: Decodable, Sendable {
        let id: String
        let header: String?
        let question: String
        let detail: String?
        let options: [Option]?
        let multiSelect: Bool?
        struct Option: Decodable, Sendable {
            let label: String
            let description: String?
        }
    }
}
struct DeepSeekState: Decodable, Sendable {
    let cursor: Int
    let active: Bool
    let running: Bool
    let pendingInput: [String]
}
struct DeepSeekHistory: Decodable, Sendable {
    let cursor: Int
    let records: [Record]
    struct Record: Decodable, Sendable { let event: DeepSeekEvent }
}
struct DeepSeekEvent: Decodable, Sendable {
    let type: String
    let seq: Int
    let time: Double
    let data: Payload

    private enum CodingKeys: String, CodingKey {
        case type, seq, time, data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        seq = try container.decode(Int.self, forKey: .seq)
        time = try container.decode(Double.self, forKey: .time)
        // Events are only used for previews and status; an unfamiliar payload shape must not
        // drop the whole history and hide every DeepSeek session.
        data = (try? container.decode(Payload.self, forKey: .data)) ?? Payload()
    }

    struct Payload: Decodable, Sendable {
        let reason: Reason?
        let message: Message?
        let name: String?
        let callId: String?

        init(reason: Reason? = nil, message: Message? = nil, name: String? = nil, callId: String? = nil) {
            self.reason = reason
            self.message = message
            self.name = name
            self.callId = callId
        }

        private enum CodingKeys: String, CodingKey {
            case reason, message, name, callId
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            reason = try? container.decodeIfPresent(Reason.self, forKey: .reason)
            message = try? container.decodeIfPresent(Message.self, forKey: .message)
            name = try? container.decodeIfPresent(String.self, forKey: .name)
            callId = try? container.decodeIfPresent(String.self, forKey: .callId)
        }

        struct Reason: Decodable, Sendable {
            let kind: String

            private enum CodingKeys: String, CodingKey { case kind }

            init(kind: String) {
                self.kind = kind
            }

            init(from decoder: Decoder) throws {
                // Harness reports some endings as a bare string instead of a `kind` object.
                if let value = try? decoder.singleValueContainer().decode(String.self) {
                    kind = value
                    return
                }
                kind = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .kind)
            }
        }

        struct Message: Decodable, Sendable {
            let content: [Content]?
            let toolCallId: String?
        }

        struct Content: Decodable, Sendable {
            let type: String
            let text: String?
            let name: String?
        }
    }
}

public struct DeepSeekTokenUsage: Decodable, Sendable, Equatable {
    public let uncachedInputTokens: Int
    public let outputTokens: Int
    public let cacheReadTokens: Int
    public let cacheWriteTokens: Int
    public var totalTokens: Int {
        uncachedInputTokens + outputTokens + cacheReadTokens + cacheWriteTokens
    }
}

public struct DeepSeekUsageSummary: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let tokens: DeepSeekTokenUsage
    public let contextTokens: Int?
    public let contextWindow: Int?
}

public struct DeepSeekRefresh: Sendable {
    public let poll: ProviderPollResult
    public let questions: [CodexQuestionRequest]
    public let usage: [DeepSeekUsageSummary]
    public let isConnected: Bool
}
