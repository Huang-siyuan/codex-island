import Darwin
import Foundation

public struct QuotaWindow: Codable, Equatable, Sendable {
    public let usedPercent: Double
    public let windowDurationMins: Int?
    public let resetsAt: TimeInterval?

    public var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
}

public struct SubscriptionQuota: Codable, Equatable, Sendable {
    public struct Credits: Codable, Equatable, Sendable {
        public let hasCredits: Bool
        public let unlimited: Bool
        public let balance: String?

        // Codex reports a decimal string in credits, not a currency amount.
        public var balanceAmount: Decimal? {
            guard let balance else { return nil }
            return Decimal(string: balance, locale: Locale(identifier: "en_US_POSIX"))
        }
    }

    public let limitId: String?
    public let limitName: String?
    public let primary: QuotaWindow?
    public let secondary: QuotaWindow?
    public let planType: String?
    public let credits: Credits?
}

public struct SubscriptionQuotaResponse: Decodable, Sendable {
    public let rateLimits: SubscriptionQuota
    public let rateLimitsByLimitId: [String: SubscriptionQuota]?
    public let accountId: String?

    public var limits: [SubscriptionQuota] {
        guard let all = rateLimitsByLimitId, !all.isEmpty else { return [rateLimits] }
        return all.keys.sorted().compactMap { all[$0] }
    }
}

public enum QuotaAlertKind: String, Sendable { case warning, exhausted, reset }

public struct QuotaAlert: Equatable, Sendable {
    public let limit: String
    public let windowMinutes: Int?
    public let kind: QuotaAlertKind
}

/// Tracks each account/window separately. A reset is reported only after a fresh server observation.
public struct QuotaAlertTracker: Sendable {
    private struct Observation: Sendable {
        var window: QuotaWindow
        var warned: Bool
        var exhausted: Bool
    }
    private var observations: [String: Observation] = [:]
    public init() {}

    public mutating func update(_ response: SubscriptionQuotaResponse, threshold: Double) -> [QuotaAlert] {
        var alerts: [QuotaAlert] = []
        let threshold = min(95, max(50, threshold))
        var keys = Set<String>()
        for limit in response.limits {
            for (slot, window) in [("primary", limit.primary), ("secondary", limit.secondary)] {
                guard let window, window.usedPercent.isFinite else { continue }
                let name = limit.limitName ?? limit.limitId ?? "Codex"
                let key = "\(response.accountId ?? "local"):\(limit.limitId ?? name):\(slot)"
                keys.insert(key)
                let old = observations[key]
                let reset = old.map {
                    // Some servers move the reset timestamp slightly while a rolling window is active.
                    window.usedPercent < $0.window.usedPercent &&
                        (window.resetsAt != $0.window.resetsAt || $0.exhausted)
                } ?? false
                var state = reset ? nil : old
                if reset, old?.warned == true || old?.exhausted == true {
                    alerts.append(QuotaAlert(limit: name, windowMinutes: window.windowDurationMins, kind: .reset))
                }
                if window.usedPercent >= 100, state?.exhausted != true {
                    alerts.append(QuotaAlert(limit: name, windowMinutes: window.windowDurationMins, kind: .exhausted))
                } else if window.usedPercent >= threshold, state?.warned != true, state?.exhausted != true {
                    alerts.append(QuotaAlert(limit: name, windowMinutes: window.windowDurationMins, kind: .warning))
                }
                state = Observation(window: window, warned: (state?.warned ?? false) || window.usedPercent >= threshold,
                                    exhausted: (state?.exhausted ?? false) || window.usedPercent >= 100)
                observations[key] = state
            }
        }
        observations = observations.filter { keys.contains($0.key) }
        return alerts
    }
}

public enum CodexLocalError: Error, LocalizedError {
    case unavailable, timedOut, invalidResponse, rejected
    public var errorDescription: String? {
        switch self {
        case .unavailable: "Codex is unavailable"
        case .timedOut: "Codex did not respond in time"
        case .invalidResponse: "Unsupported Codex response"
        case .rejected: "Codex rejected the request"
        }
    }
}

/// Uses the installed CLI's authenticated account API; never derives subscription limits from token totals.
public enum SubscriptionQuotaReader {
    public static func read(executable: URL) async throws -> SubscriptionQuotaResponse {
        try await Task.detached(priority: .utility) { try readSynchronously(executable: executable) }.value
    }

    private static func readSynchronously(executable: URL) throws -> SubscriptionQuotaResponse {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            // The timeout also bounds shutdown of a wedged app-server.
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
        }
        try input.fileHandleForWriting.write(contentsOf: Data(#"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"codex_island","version":"1.0"},"capabilities":{}}}"#.utf8) + Data([10]))
        let deadline = Date().addingTimeInterval(20)
        var buffer = Data()
        while Date() < deadline {
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, 250) > 0 else { continue }
            var bytes = [UInt8](repeating: 0, count: 8192)
            let count = Darwin.read(descriptor.fd, &bytes, bytes.count)
            guard count > 0 else { throw CodexLocalError.unavailable }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count <= 4 * 1024 * 1024 else { throw CodexLocalError.invalidResponse }
            while let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                let response = try JSONDecoder().decode(RPCResponse.self, from: line)
                guard let id = response.id else { continue }
                guard response.error == nil else { throw CodexLocalError.rejected }
                if id == 1 {
                    try input.fileHandleForWriting.write(contentsOf: Data("{\"method\":\"initialized\"}\n{\"id\":2,\"method\":\"account/rateLimits/read\"}\n".utf8))
                } else if id == 2, let result = response.result {
                    return result
                }
            }
        }
        throw CodexLocalError.timedOut
    }

    private struct RPCResponse: Decodable {
        let id: Int?
        let error: RPCError?
        let result: SubscriptionQuotaResponse?
        enum CodingKeys: String, CodingKey { case id, error, result }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decodeIfPresent(Int.self, forKey: .id)
            error = try values.decodeIfPresent(RPCError.self, forKey: .error)
            result = id == 2 ? try values.decodeIfPresent(SubscriptionQuotaResponse.self, forKey: .result) : nil
        }
    }
    private struct RPCError: Decodable { let code: Int }
}
