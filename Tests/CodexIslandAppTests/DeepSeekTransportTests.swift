import Foundation
import Testing

@testable import CodexIslandCore

/// Requests are captured in a per-test fixture; no live account or session is mutated.
private final class DeepSeekMockURLProtocol: URLProtocol, @unchecked Sendable {
    static let fixture = DeepSeekFixture()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "127.0.0.1" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            var body = request.httpBody
            if body == nil, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var bytes = Data()
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                defer { buffer.deallocate() }
                while stream.hasBytesAvailable {
                    let count = stream.read(buffer, maxLength: 4096)
                    if count <= 0 { break }
                    bytes.append(buffer, count: count)
                }
                body = bytes
            }
            let data = try Self.fixture.respond(body: body)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private final class DeepSeekFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [IPCValue] = []
    private var accepted = true
    private var answered = false
    func reset(accept: Bool = true) {
        lock.withLock {
            captured = []
            accepted = accept
            answered = false
        }
    }
    var requests: [IPCValue] { lock.withLock { captured } }
    func respond(body: Data?) throws -> Data {
        try lock.withLock {
            guard let body, !body.isEmpty else { return Data() }
            let request = try JSONDecoder().decode(IPCValue.self, from: body)
            captured.append(request)
            let method = request["method"].string
            let value: IPCValue
            if method == "session/projections" {
                let active =
                    answered
                    ? "[]"
                    : #"[{"callId":"c","state":"continued","questions":[{"id":"q","question":"Choose","options":[{"label":"A"}]}]}]"#
                value = try JSONDecoder().decode(
                    IPCValue.self,
                    from: Data(
                        "{\"kind\":\"sequenced\",\"values\":{\"userQuestions\":{\"active\":\(active)}}}".utf8))
            } else if method == "account/getState" {
                value = .object(["status": .string("credential-stored")])
            } else if method == "account/getBalance" {
                value = .object([
                    "status": .string("ready"),
                    "value": .array([
                        .object(["currency": .string("CNY"), "balance": .string("12.3400")])
                    ]), "bonusWallets": .array([]),
                ])
            } else if method == "userQuestions/answer" {
                answered = accepted
                value = .bool(accepted)
            } else {
                value = .null
            }
            return try JSONEncoder().encode(
                IPCValue.object([
                    "type": .string("server-response"), "rpcId": request["rpcId"],
                    "result": .object(["ok": .bool(true), "value": value]),
                ]))
        }
    }
}

@Suite(.serialized)
struct DeepSeekTransportTests {
    private func withTransport(_ body: (DeepSeekTransport) async throws -> Void) async throws {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("http://127.0.0.1:3080/?token=synthetic".utf8).write(to: log)
        defer { try? FileManager.default.removeItem(at: log) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DeepSeekMockURLProtocol.self]
        try await body(DeepSeekTransport(logURL: log, configuration: config))
    }

    @Test func balanceKeepsDecimalPrecisionAndNeverReadsAccountCredentials() async throws {
        try await withTransport { transport in
            DeepSeekMockURLProtocol.fixture.reset()
            let snapshot = await DeepSeekAccountClient(transport: transport).refresh()
            guard case .balance(let balance) = snapshot else {
                Issue.record("Expected a wallet response")
                return
            }
            #expect(balance.value?.first?.balance == "12.3400")
            #expect(
                DeepSeekMockURLProtocol.fixture.requests.map { $0["method"].string } == [
                    "account/getState", "account/getBalance",
                ])
        }
    }

    @Test func continuedAnswersRequireAcceptanceAndAuthoritativeRemoval() async throws {
        try await withTransport { transport in
            DeepSeekMockURLProtocol.fixture.reset()
            let projection = try await transport.call(
                "session/projections", arguments: DeepSeekEmpty(), returning: DeepSeekProjection.self)
            let request = try #require(
                DeepSeekClient.questions(sessionID: "s", projection: projection).first)
            let client = DeepSeekClient(transport: transport)
            try await client.answer(request, answers: ["q": "A"])
            let writes = DeepSeekMockURLProtocol.fixture.requests.filter {
                $0["method"].string == "userQuestions/answer"
            }
            #expect(writes.count == 1)
            #expect(
                writes.first?["payload"]["args"]["answer"]["answers"].array?.first?["selected"]
                    == .array([.string("A")]))
            DeepSeekMockURLProtocol.fixture.reset(accept: false)
            await #expect(throws: DeepSeekError.self) {
                try await client.answer(request, answers: ["q": "A"])
            }
            #expect(
                DeepSeekMockURLProtocol.fixture.requests.filter {
                    $0["method"].string == "userQuestions/answer"
                }.count == 1)
        }
    }

    @Test func liveQuestionsUseOwnedEventAndDelegateApprovalsWithoutAnswering() async throws {
        try await withTransport { transport in
            DeepSeekMockURLProtocol.fixture.reset()
            let events = DeepSeekEvents(transport: transport)
            func frame(_ json: String) throws -> DeepSeekEvents.Frame {
                try JSONDecoder().decode(DeepSeekEvents.Frame.self, from: Data(json.utf8))
            }
            try await events.receive(frame(#"{"type":"ready","clientId":"peer"}"#))
            try await events.receive(
                frame(
                    #"{"type":"waterfall","event":"approval/request","eventId":"approval","agentId":"s","request":{}}"#
                ))
            #expect(
                DeepSeekMockURLProtocol.fixture.requests.last?["payload"]["args"]["outcome"]["kind"].string
                    == "next")
            try await events.receive(
                frame(
                    #"{"type":"waterfall","event":"user-questions/request","eventId":"event","agentId":"s","request":{"wait":{"callId":"c"}}}"#
                ))
            try await events.answer(
                sessionID: "s", callID: "c", value: DeepSeekMultipleAnswer(selected: ["A"]))
            let sent = try #require(DeepSeekMockURLProtocol.fixture.requests.last)
            #expect(sent["method"].string == "$events/result")
            #expect(sent["payload"]["args"]["clientId"].string == "peer")
            #expect(sent["payload"]["args"]["eventId"].string == "event")
            #expect(sent["payload"]["args"]["outcome"]["kind"].string == "result")
            await #expect(throws: DeepSeekError.self) {
                try await events.answer(sessionID: "s", callID: "c", value: DeepSeekEmpty())
            }
            try await events.receive(
                frame(
                    #"{"type":"waterfall","event":"user-questions/request","eventId":"cancelled","agentId":"s","request":{"wait":{"callId":"d"}}}"#
                ))
            try await events.receive(frame(#"{"type":"cancel","eventId":"cancelled"}"#))
            await #expect(throws: DeepSeekError.self) {
                try await events.answer(sessionID: "s", callID: "d", value: DeepSeekEmpty())
            }
            await events.close()
        }
    }
}
