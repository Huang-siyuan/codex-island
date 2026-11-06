import Foundation

public struct DeepSeekBalance: Decodable, Sendable, Equatable {
    public let status: String
    public let value: [Wallet]?
    public let bonusWallets: [Wallet]?
    public struct Wallet: Decodable, Sendable, Equatable {
        public let currency: String
        public let balance: String
    }
}

public enum DeepSeekAccountSnapshot: Sendable, Equatable {
    case signedOut
    case balance(DeepSeekBalance)
    case unavailable
}

/// Balance is queried through the authenticated Harness host; account credentials never leave it.
public actor DeepSeekAccountClient {
    private let transport: DeepSeekTransport
    public init(transport: DeepSeekTransport = DeepSeekTransport()) { self.transport = transport }

    public func refresh() async -> DeepSeekAccountSnapshot {
        struct State: Decodable, Sendable { let status: String }
        struct Arguments: Encodable, Sendable {
            let client: Client
            struct Client: Encodable, Sendable {
                let version: String
                let locale: String
                let timezoneOffsetSeconds: Int
            }
        }
        do {
            let state = try await transport.call(
                "account/getState", arguments: DeepSeekEmpty(), returning: State.self)
            guard state.status == "credential-stored" else { return .signedOut }
            let metadata = Arguments.Client(
                version: "codex-island", locale: Locale.current.identifier,
                timezoneOffsetSeconds: TimeZone.current.secondsFromGMT())
            let balance = try await transport.call(
                "account/getBalance", arguments: Arguments(client: metadata),
                returning: DeepSeekBalance.self)
            return balance.status == "ready" ? .balance(balance) : .unavailable
        } catch { return .unavailable }
    }
}
