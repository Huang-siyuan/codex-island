import Foundation

public enum DeepSeekError: Error, LocalizedError {
    case unavailable, authentication, invalidResponse, rejected

    public var errorDescription: String? {
        switch self {
        case .unavailable: return "DeepSeek Harness is unavailable"
        case .authentication: return "Reopen DeepSeek Harness to reconnect"
        case .invalidResponse: return "Unsupported DeepSeek Harness response"
        case .rejected: return "DeepSeek Harness did not accept the request"
        }
    }
}

/// Uses the desktop host's startup handoff, never the model/account credentials.
/// Ephemeral cookies and same-origin redirects keep the launch token local.
public actor DeepSeekTransport {
    private let logURL: URL
    private let session: URLSession
    private var authenticatedURL: URL?

    public init(
        logURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DeepSeek Harness/deepseek-harness.log"),
        configuration: URLSessionConfiguration = .ephemeral
    ) {
        self.logURL = logURL
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 5
        self.session = URLSession(
            configuration: configuration, delegate: LoopbackRedirectPolicy(), delegateQueue: nil)
    }

    public static func launchURL(in text: String) -> URL? {
        guard
            let expression = try? NSRegularExpression(
                pattern: #"http://(?:127\.0\.0\.1|localhost):[0-9]+/\?token=[A-Za-z0-9_%.-]+"#),
            let match = expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
            let range = Range(match.range, in: text), let url = URL(string: String(text[range])),
            let port = url.port, (1...65535).contains(port)
        else { return nil }
        return url
    }

    public func call<Arguments: Encodable & Sendable, Value: Decodable & Sendable>(
        _ method: String, arguments: Arguments, returning: Value.Type
    ) async throws -> Value {
        for attempt in 0..<2 {
            let launch = try discover()
            if authenticatedURL != launch {
                let (_, response) = try await session.data(from: launch)
                guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                    throw DeepSeekError.authentication
                }
                authenticatedURL = launch
            }
            var components = URLComponents(url: launch, resolvingAgainstBaseURL: false)!
            components.query = nil
            components.path = "/api/" + method
            guard let endpoint = components.url else { throw DeepSeekError.invalidResponse }
            let rpcID = UUID().uuidString
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(
                RPCRequest(rpcId: rpcID, method: method, payload: .init(args: arguments)))
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw DeepSeekError.invalidResponse }
            if response.statusCode == 401, attempt == 0 {
                authenticatedURL = nil
                continue
            }
            guard response.statusCode == 200 else { throw DeepSeekError.unavailable }
            let envelope = try JSONDecoder().decode(RPCResponse<Value>.self, from: data)
            guard envelope.type == "server-response", envelope.rpcId == rpcID else {
                throw DeepSeekError.invalidResponse
            }
            guard envelope.result.ok else { throw DeepSeekError.rejected }
            if Value.self == DeepSeekEmpty.self, let empty = DeepSeekEmpty() as? Value { return empty }
            guard let value = envelope.result.value else { throw DeepSeekError.invalidResponse }
            return value
        }
        throw DeepSeekError.authentication
    }

    func openEventSocket() async throws -> URLSessionWebSocketTask {
        // refresh() authenticates HTTP before opening the stream; both share ephemeral cookies.
        guard let authenticatedURL, authenticatedURL == (try discover()) else {
            throw DeepSeekError.authentication
        }
        var components = URLComponents(url: authenticatedURL, resolvingAgainstBaseURL: false)!
        components.scheme = "ws"
        components.query = nil
        components.path = "/api/remote.mux"
        guard let url = components.url else { throw DeepSeekError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        let cookies = session.configuration.httpCookieStorage?.cookies(for: authenticatedURL) ?? []
        for (key, value) in HTTPCookie.requestHeaderFields(with: cookies) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let socket = session.webSocketTask(with: request)
        socket.resume()
        return socket
    }

    private func discover() throws -> URL {
        guard let handle = try? FileHandle(forReadingFrom: logURL) else {
            throw DeepSeekError.unavailable
        }
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        // Logs can grow indefinitely; the most recent startup is near the tail.
        try handle.seek(toOffset: size > 262_144 ? size - 262_144 : 0)
        let data = try handle.readToEnd() ?? Data()
        guard let url = Self.launchURL(in: String(decoding: data, as: UTF8.self)) else {
            throw DeepSeekError.unavailable
        }
        return url
    }
}

private struct RPCRequest<Arguments: Encodable>: Encodable {
    let type = "client-request"
    let rpcId: String
    let method: String
    let payload: Payload
    struct Payload: Encodable { let args: Arguments }
}

private struct RPCResponse<Value: Decodable>: Decodable {
    let type: String
    let rpcId: String
    let result: Result
    struct Result: Decodable {
        let ok: Bool
        let value: Value?
    }
}

private final class LoopbackRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        let origin = task.originalRequest?.url
        let target = request.url
        let sameOrigin =
            target?.scheme == "http" && target?.host == origin?.host && target?.port == origin?.port
        completionHandler(sameOrigin ? request : nil)
    }
}
