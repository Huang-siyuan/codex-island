import Darwin
import Foundation

/// A follower of the existing desktop conversation owner. Does not resume or start a second turn.
public actor CodexDesktopClient {
    private let socketURL: URL
    private var descriptor: Int32 = -1
    private var clientID = "codex-island"
    private var buffer = Data()
    private var followed = Set<String>()
    private var streams: [String: CodexConversationStream] = [:]
    private var responses: [String: IPCValue] = [:]
    private var pendingResponses = Set<String>()
    private var nextConnectionAttempt = Date.distantPast
    private static let maximumFrameSize = 32 * 1024 * 1024

    public init(codexHome: URL = AppEnvironment.default.codexHome) {
        socketURL = codexHome.appendingPathComponent("ipc/ipc.sock")
    }

    public var isConnected: Bool { descriptor >= 0 }

    public func close() {
        if descriptor >= 0 { Darwin.close(descriptor) }
        descriptor = -1
        buffer.removeAll()
        followed.removeAll()
        streams.removeAll()
        responses.removeAll()
        pendingResponses.removeAll()
    }

    public func refresh(threadIDs: Set<String>) -> [CodexQuestionRequest] {
        do {
            if descriptor < 0 {
                guard Date() >= nextConnectionAttempt else { return [] }
                nextConnectionAttempt = Date().addingTimeInterval(5)
                try connect()
            }
            for id in followed.subtracting(threadIDs) {
                try follow(id, enabled: false)
                streams.removeValue(forKey: id)
            }
            for id in threadIDs.subtracting(followed) { try follow(id, enabled: true) }
            followed = threadIDs
            try drain(waitMilliseconds: 25)
            return questions()
        } catch {
            close()
            return []
        }
    }

    public func answer(_ request: CodexQuestionRequest, answers: [String: String]) async throws {
        guard descriptor >= 0, request.validates(answers) else { throw CodexLocalError.rejected }
        try drain(waitMilliseconds: 0)
        guard questions().contains(request) else { throw CodexLocalError.rejected }
        let id = UUID().uuidString
        pendingResponses.insert(id)
        defer { pendingResponses.remove(id); responses.removeValue(forKey: id) }
        let answerValues = Dictionary(uniqueKeysWithValues: request.questions.map { question in
            (question.id, IPCValue.object(["answers": .array([.string(answers[question.id]!.trimmingCharacters(in: .whitespacesAndNewlines))])]))
        })
        try send(.object([
            "type": .string("request"), "requestId": .string(id), "sourceClientId": .string(clientID),
            "targetClientId": .string(request.ownerID), "method": .string("thread-follower-submit-user-input"),
            "version": .number(1), "params": .object([
                "conversationId": .string(request.threadID), "requestId": request.requestID,
                "response": .object(["answers": .object(answerValues)])
            ])
        ]))
        let deadline = Date().addingTimeInterval(8)
        var acknowledged = false
        while Date() < deadline {
            try Task.checkCancellation()
            guard descriptor >= 0 else { throw CodexLocalError.unavailable }
            try drain(waitMilliseconds: 0)
            if let response = responses.removeValue(forKey: id) {
                guard response["resultType"].string == "success", response["result"]["ok"] == .bool(true) else { throw CodexLocalError.rejected }
                acknowledged = true
            }
            // The owner acknowledges dispatch before applying it. Wait for the authoritative removal too.
            if acknowledged, streams[request.threadID]?.ownerID == request.ownerID, !questions().contains(request) { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw CodexLocalError.timedOut
    }

    private func questions() -> [CodexQuestionRequest] {
        followed.sorted().flatMap { streams[$0]?.questions(threadID: $0) ?? [] }
    }

    private func connect() throws {
        var info = stat()
        guard lstat(socketURL.path, &info) == 0, info.st_uid == getuid(),
              info.st_mode & S_IFMT == S_IFSOCK else { throw CodexLocalError.unavailable }
        var parent = stat()
        guard lstat(socketURL.deletingLastPathComponent().path, &parent) == 0,
              parent.st_uid == getuid(), parent.st_mode & S_IFMT == S_IFDIR,
              parent.st_mode & 0o022 == 0 else { throw CodexLocalError.unavailable }
        descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw CodexLocalError.unavailable }
        var noSignal: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array(socketURL.path.utf8CString)
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw CodexLocalError.unavailable }
        withUnsafeMutableBytes(of: &address.sun_path) { target in target.copyBytes(from: path.map { UInt8(bitPattern: $0) }) }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else { throw CodexLocalError.unavailable }
        let id = UUID().uuidString
        pendingResponses.insert(id)
        defer { pendingResponses.remove(id); responses.removeValue(forKey: id) }
        try send(.object(["type": .string("request"), "requestId": .string(id), "sourceClientId": .string(clientID),
                          "version": .number(0), "method": .string("initialize"), "params": .object(["clientType": .string("codex-island")])]))
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            try drain(waitMilliseconds: 100)
            if let response = responses.removeValue(forKey: id), let clientID = response["result"]["clientId"].string {
                self.clientID = clientID
                return
            }
        }
        throw CodexLocalError.timedOut
    }

    private func follow(_ threadID: String, enabled: Bool) throws {
        try send(.object(["type": .string("broadcast"), "sourceClientId": .string(clientID), "version": .number(1),
                          "method": .string("thread-stream-following-changed"), "params": .object([
                            "conversationId": .string(threadID), "hostId": .string("local"), "following": .bool(enabled)
                          ])]))
    }

    private func send(_ value: IPCValue) throws {
        let data = try JSONEncoder().encode(value)
        var length = UInt32(data.count).littleEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(data)
        try frame.withUnsafeBytes { bytes in
            var sent = 0
            while sent < bytes.count {
                let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: sent), bytes.count - sent)
                guard count > 0 else { throw CodexLocalError.unavailable }
                sent += count
            }
        }
    }

    private func drain(waitMilliseconds: Int32) throws {
        var fd = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        var wait = waitMilliseconds
        // Bound work per poll, even if another conversation is streaming continuously.
        for _ in 0..<64 {
            guard poll(&fd, 1, wait) > 0 else { break }
            wait = 0
            var bytes = [UInt8](repeating: 0, count: 65536)
            let count = Darwin.read(descriptor, &bytes, bytes.count)
            guard count > 0 else { throw CodexLocalError.unavailable }
            buffer.append(contentsOf: bytes.prefix(count))
            while buffer.count >= 4 {
                let length = buffer.prefix(4).enumerated().reduce(0) { $0 | Int($1.element) << ($1.offset * 8) }
                guard length > 0, length <= Self.maximumFrameSize else { throw CodexLocalError.invalidResponse }
                guard buffer.count >= length + 4 else { break }
                let data = Data(buffer.dropFirst(4).prefix(length))
                buffer.removeFirst(length + 4)
                try receive(JSONDecoder().decode(IPCValue.self, from: data))
            }
        }
    }

    private func receive(_ message: IPCValue) throws {
        switch message["type"].string {
        case "response":
            if let id = message["requestId"].string, pendingResponses.contains(id) { responses[id] = message }
        case "client-discovery-request":
            try send(.object(["type": .string("client-discovery-response"), "requestId": message["requestId"], "response": .object(["canHandle": .bool(false)])]))
        case "broadcast":
            if message["method"].string == "client-status-changed", message["params"]["status"].string == "disconnected" {
                streams = streams.filter { $0.value.ownerID != message["params"]["clientId"].string }
            }
            guard message["method"].string == "thread-stream-state-changed",
                  message["params"]["hostId"].string == "local", let thread = message["params"]["conversationId"].string,
                  followed.contains(thread), let owner = message["sourceClientId"].string else { return }
            guard message["version"].number == 11 else {
                streams.removeValue(forKey: thread)
                return
            }
            do {
                var stream = streams[thread] ?? CodexConversationStream()
                try stream.receive(change: message["params"]["change"], ownerID: owner)
                streams[thread] = stream
            } catch {
                streams.removeValue(forKey: thread)
                try follow(thread, enabled: false)
                try follow(thread, enabled: true)
            }
        default: break
        }
    }
}
