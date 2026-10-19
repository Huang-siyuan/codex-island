import CryptoKit
import Foundation

/// Read-only adapter for the desktop app's versioned unread state, scoped to this
/// account and the ordinary local execution host. Unknown schemas stay unknown.
public final class CodexUnreadStateReader {
    private let globalStateURL: URL
    private let authURL: URL
    private let databaseURL: URL
    private var lastVersion: DataSourceVersion?
    private var cachedCount: Int?

    public init(environment: AppEnvironment = .default) {
        globalStateURL = environment.codexHome.appendingPathComponent(".codex-global-state.json")
        authURL = environment.codexHome.appendingPathComponent("auth.json")
        databaseURL = environment.stateStoreURL
    }

    public func readCount() -> Int? {
        let version = DataSourceVersion.capture(files: [
            globalStateURL, authURL, databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
        ])
        if version == lastVersion {
            return cachedCount
        }
        // Do not retain a count from another account, or turn a failed read into zero.
        cachedCount = try? loadCount()
        lastVersion = version
        return cachedCount
    }

    private func loadCount() throws -> Int? {
        let stateData = try Data(contentsOf: globalStateURL)
        let authData = try Data(contentsOf: authURL)
        guard let unreadIDs = try Self.unreadThreadIDs(stateData: stateData, authData: authData),
              FileManager.default.fileExists(atPath: databaseURL.path) else {
            return nil
        }
        // Include older unread threads too, but exclude archived/deleted threads.
        let threads: [LocalThread] = try SQLiteShell().query(
            databaseURL: databaseURL,
            query: "select id from threads where archived = 0;"
        )
        return unreadIDs.intersection(threads.map(\.id)).count
    }

    static func unreadThreadIDs(stateData: Data, authData: Data) throws -> Set<String>? {
        let state = try JSONDecoder().decode(DesktopState.self, from: stateData)
        guard let readState = state.readState, readState.version == 1,
              let identityKey = try identityKey(authData: authData),
              let ids = readState.unreadByIdentity[identityKey]?[localExecutionHostKey] else {
            return nil
        }
        return Set(ids.filter { !$0.isEmpty })
    }

    // Matches Codex desktop's SHA-256(JSON.stringify([kind, hostId, websocketURL])).
    // Custom websocket hosts and remote hosts must not be combined with local data.
    static let localExecutionHostKey = "local:" + hash(["local", "local", nil])

    static func identityKey(authData: Data) throws -> String? {
        let auth = try JSONDecoder().decode(AuthState.self, from: authData)
        guard ["chatgpt", "chatgptAuthTokens"].contains(auth.authMode),
              let token = auth.tokens?.accessToken else {
            return nil
        }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            return nil
        }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else {
            return nil
        }
        let claims = try JSONDecoder().decode(TokenClaims.self, from: data).auth
        guard let accountID = claims.chatGPTAccountID ?? claims.accountID,
              let userID = claims.userID ?? claims.chatGPTUserID,
              !accountID.isEmpty, !userID.isEmpty,
              auth.tokens?.accountID == nil || auth.tokens?.accountID == accountID else {
            return nil
        }
        // The token is only decoded to select a local bucket; it is never sent,
        // logged, or retained. This is not an authentication or token validation step.
        return hash(["chatgpt", accountID, userID])
    }

    private static func hash(_ values: [String?]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(values) else {
            return ""
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct LocalThread: Decodable {
    let id: String
}

private struct DesktopState: Decodable {
    let readState: ThreadReadState?

    enum CodingKeys: String, CodingKey {
        case readState = "electron-thread-read-state-v1"
    }
}

private struct ThreadReadState: Decodable {
    let version: Int
    let unreadByIdentity: [String: [String: [String]]]
}

private struct AuthState: Decodable {
    let authMode: String
    let tokens: AuthTokens?

    enum CodingKeys: String, CodingKey {
        case authMode = "auth_mode"
        case tokens
    }
}

private struct AuthTokens: Decodable {
    let accessToken: String?
    let accountID: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case accountID = "account_id"
    }
}

private struct TokenClaims: Decodable {
    let auth: IdentityClaims

    enum CodingKeys: String, CodingKey {
        case auth = "https://api.openai.com/auth"
    }
}

private struct IdentityClaims: Decodable {
    let chatGPTAccountID: String?
    let accountID: String?
    let userID: String?
    let chatGPTUserID: String?

    enum CodingKeys: String, CodingKey {
        case chatGPTAccountID = "chatgpt_account_id"
        case accountID = "account_id"
        case userID = "user_id"
        case chatGPTUserID = "chatgpt_user_id"
    }
}
