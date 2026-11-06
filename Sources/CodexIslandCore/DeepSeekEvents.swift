import Foundation

/// Only question waterfalls are retained. Other interactions remain with the native client.
actor DeepSeekEvents {
    private let transport: DeepSeekTransport
    private var socket: URLSessionWebSocketTask?
    private var reader: Task<Void, Never>?
    private var clientID: String?
    private var pending: [String: Frame] = [:]

    struct Frame: Decodable, Sendable {
        let type: String
        let clientId: String?
        let event: String?
        let eventId: String?
        let agentId: String?
        let request: Request?
        struct Request: Decodable, Sendable {
            let wait: Wait?
            struct Wait: Decodable, Sendable { let callId: String? }
        }
    }
    private struct Wire: Decodable {
        let type: String
        let value: Frame?
    }
    private struct Open: Encodable {
        let type = "open"
        let streamId = "island-questions"
        let endpoint = "$events"
        let payload = Payload()
        struct Payload: Encodable { let args = DeepSeekEmpty() }
    }
    private struct ResultArguments<Value: Encodable & Sendable>: Encodable, Sendable {
        let clientId: String
        let eventId: String
        let outcome: Outcome
        struct Outcome: Encodable, Sendable {
            let kind: String
            let value: Value?
        }
    }

    init(transport: DeepSeekTransport) { self.transport = transport }

    func connect() async throws {
        guard socket == nil else { return }
        let task = try await transport.openEventSocket()
        socket = task
        do {
            try await task.send(.string(String(decoding: JSONEncoder().encode(Open()), as: UTF8.self)))
            reader = Task { [weak self] in
                do {
                    while !Task.isCancelled {
                        let message = try await task.receive()
                        let data: Data
                        switch message {
                        case .data(let bytes): data = bytes
                        case .string(let text): data = Data(text.utf8)
                        @unknown default: throw DeepSeekError.invalidResponse
                        }
                        let wire = try JSONDecoder().decode(Wire.self, from: data)
                        guard wire.type == "item", let frame = wire.value else {
                            throw DeepSeekError.invalidResponse
                        }
                        try await self?.receive(frame)
                    }
                } catch {
                    await self?.close()
                }
            }
        } catch {
            close()
            throw error
        }
    }

    var isReady: Bool { clientID != nil }

    func close() {
        reader?.cancel()
        reader = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        clientID = nil
        pending.removeAll()
    }

    func receive(_ frame: Frame) async throws {
        if frame.type == "ready" {
            clientID = frame.clientId
        } else if frame.type == "cancel", let id = frame.eventId {
            pending.removeValue(forKey: id)
        } else if frame.type == "waterfall", let id = frame.eventId {
            if frame.event == "user-questions/request", frame.request?.wait?.callId != nil {
                pending[id] = frame
            } else if let clientID {
                let _: DeepSeekEmpty = try await transport.call(
                    "$events/result",
                    arguments: ResultArguments<DeepSeekEmpty>(
                        clientId: clientID, eventId: id, outcome: .init(kind: "next", value: nil)),
                    returning: DeepSeekEmpty.self)
            }
        }
    }

    func answer<Value: Encodable & Sendable>(sessionID: String, callID: String, value: Value)
        async throws
    {
        guard let clientID,
            let frame = pending.values.first(where: {
                $0.agentId == sessionID && $0.request?.wait?.callId == callID
            }), let eventID = frame.eventId
        else { throw DeepSeekError.rejected }
        let _: DeepSeekEmpty = try await transport.call(
            "$events/result",
            arguments: ResultArguments(
                clientId: clientID, eventId: eventID, outcome: .init(kind: "result", value: value)),
            returning: DeepSeekEmpty.self)
        pending.removeValue(forKey: eventID)
    }
}
