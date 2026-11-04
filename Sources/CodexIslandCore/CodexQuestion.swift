import Foundation

public struct CodexQuestion: Codable, Equatable, Sendable, Identifiable {
    public struct Option: Codable, Equatable, Sendable, Identifiable {
        public let label: String
        public let description: String
        public var id: String { label }
    }
    public let id: String
    public let header: String
    public let question: String
    public let isOther: Bool?
    public let isSecret: Bool?
    public let options: [Option]?
}

public struct CodexQuestionRequest: Equatable, Sendable, Identifiable {
    public let threadID: String
    public let requestID: IPCValue
    public let ownerID: String
    public let questions: [CodexQuestion]
    public var id: String { "\(threadID):\(requestID)" }

    public func validates(_ answers: [String: String]) -> Bool {
        !questions.isEmpty && questions.allSatisfy { question in
            guard let answer = answers[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !answer.isEmpty else { return false }
            let options = question.options ?? []
            return options.isEmpty || question.isOther != false || options.contains { $0.label == answer }
        }
    }
}

/// Dynamic JSON is confined to the desktop IPC transport, whose snapshot patches address arbitrary fields.
public enum IPCValue: Codable, Equatable, Sendable {
    case object([String: IPCValue]), array([IPCValue]), string(String), number(Double), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let v = try? container.decode(Bool.self) { self = .bool(v) }
        else if let v = try? container.decode(Double.self) { self = .number(v) }
        else if let v = try? container.decode(String.self) { self = .string(v) }
        else if let v = try? container.decode([IPCValue].self) { self = .array(v) }
        else { self = .object(try container.decode([String: IPCValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }

    public subscript(_ key: String) -> IPCValue {
        guard case .object(let values) = self else { return .null }
        return values[key] ?? .null
    }
    public var string: String? { if case .string(let value) = self { value } else { nil } }
    public var array: [IPCValue]? { if case .array(let value) = self { value } else { nil } }
    public var number: Double? { if case .number(let value) = self { value } else { nil } }

    public mutating func applyPatch(path: ArraySlice<IPCValue>, operation: String, value: IPCValue) throws {
        guard let key = path.first else {
            guard operation == "replace" || operation == "add" else { throw CodexLocalError.invalidResponse }
            self = value
            return
        }
        switch self {
        case .object(var values):
            guard let key = key.string else { throw CodexLocalError.invalidResponse }
            if path.count == 1, operation == "remove" {
                guard values.removeValue(forKey: key) != nil else { throw CodexLocalError.invalidResponse }
            } else {
                var child = values[key] ?? .null
                try child.applyPatch(path: path.dropFirst(), operation: operation, value: value)
                values[key] = child
            }
            self = .object(values)
        case .array(var values):
            guard let indexValue = key.number, indexValue >= 0, indexValue < Double(Int.max), indexValue.rounded() == indexValue else { throw CodexLocalError.invalidResponse }
            let index = Int(indexValue)
            if path.count == 1, operation == "add", index <= values.count { values.insert(value, at: index) }
            else {
                guard values.indices.contains(index) else { throw CodexLocalError.invalidResponse }
                if path.count == 1, operation == "remove" { values.remove(at: index) }
                else { try values[index].applyPatch(path: path.dropFirst(), operation: operation, value: value) }
            }
            self = .array(values)
        default: throw CodexLocalError.invalidResponse
        }
    }
}

public struct CodexConversationStream: Sendable {
    public private(set) var state: IPCValue = .null
    public private(set) var revision: Double?
    public private(set) var ownerID: String?

    public init() {}

    public mutating func receive(change: IPCValue, ownerID: String) throws {
        guard let revision = change["revision"].number else { throw CodexLocalError.invalidResponse }
        if change["type"].string == "snapshot" {
            state = change["conversationState"]
        } else {
            guard self.ownerID == ownerID, self.revision == change["baseRevision"].number,
                  let patches = change["patches"].array else { throw CodexLocalError.invalidResponse }
            var next = state
            for patch in patches {
                guard let path = patch["path"].array, let operation = patch["op"].string else { throw CodexLocalError.invalidResponse }
                try next.applyPatch(path: path[...], operation: operation, value: patch["value"])
            }
            state = next
        }
        self.revision = revision
        self.ownerID = ownerID
    }

    public func questions(threadID: String) -> [CodexQuestionRequest] {
        guard let ownerID else { return [] }
        return (state["requests"].array ?? []).compactMap { request in
            guard request["method"].string == "item/tool/requestUserInput",
                  request["params"]["threadId"].string == threadID,
                  request["id"] != .null,
                  let data = try? JSONEncoder().encode(request["params"]["questions"]),
                  let questions = try? JSONDecoder().decode([CodexQuestion].self, from: data), !questions.isEmpty else { return nil }
            return CodexQuestionRequest(threadID: threadID, requestID: request["id"], ownerID: ownerID, questions: questions)
        }
    }
}
