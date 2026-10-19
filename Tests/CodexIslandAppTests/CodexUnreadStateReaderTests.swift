import Foundation
import SQLite3
import Testing
@testable import CodexIslandCore

@Test
func unreadStateIsScopedToCurrentAccountAndLocalHost() throws {
    let auth = try unreadAuth(account: "account-one")
    let identity = try #require(try CodexUnreadStateReader.identityKey(authData: auth))
    let otherIdentity = try #require(try CodexUnreadStateReader.identityKey(authData: unreadAuth(account: "account-two")))
    let data = try unreadState(buckets: [
        identity: [CodexUnreadStateReader.localExecutionHostKey: ["one", "one", "two"], "remote:host": ["remote"]],
        otherIdentity: [CodexUnreadStateReader.localExecutionHostKey: ["other-account"]],
    ])
    #expect(try CodexUnreadStateReader.unreadThreadIDs(stateData: data, authData: auth) == ["one", "two"])
    #expect(CodexUnreadStateReader.localExecutionHostKey == "local:092af2cb59bdd804c6f7f1cd1d85464b682974e43cd517397d25510024034d1c")
}

@Test
func unreadStateDoesNotGuessWhenAccountHostOrSchemaIsUnknown() throws {
    let auth = try unreadAuth()
    let identity = try #require(try CodexUnreadStateReader.identityKey(authData: auth))
    let unknownAccount = try unreadState(buckets: ["someone-else": [CodexUnreadStateReader.localExecutionHostKey: ["one"]]])
    let unknownHost = try unreadState(buckets: [identity: ["local:custom-websocket": ["one"]]])
    let futureSchema = try unreadState(buckets: [identity: [CodexUnreadStateReader.localExecutionHostKey: ["one"]]], version: 2)
    for state in [unknownAccount, unknownHost, futureSchema, Data("{}".utf8)] {
        #expect(try CodexUnreadStateReader.unreadThreadIDs(stateData: state, authData: auth) == nil)
    }
    #expect(try CodexUnreadStateReader.identityKey(authData: Data(#"{"auth_mode":"apikey"}"#.utf8)) == nil)
}

@Test
func unreadCountIncludesOlderThreadsAndDropsArchivedOrDeletedThreads() throws {
    let fixture = try UnreadFixture()
    defer { fixture.remove() }
    let ids = (1...12).map { "thread-\($0)" }
    for id in ids {
        try fixture.execute("insert into threads values ('\(id)', 0)")
    }
    try fixture.execute("insert into threads values ('archived', 1)")
    try fixture.writeState(ids: ids + ["archived", "deleted", "thread-1"])
    #expect(fixture.reader().readCount() == 12)
}

@Test
func unreadCountRefreshesAfterReadChangesAndAccountSwitch() throws {
    let fixture = try UnreadFixture()
    defer { fixture.remove() }
    try fixture.execute("insert into threads values ('one', 0), ('two', 0)")
    try fixture.writeState(ids: ["one", "two"])
    let reader = fixture.reader()
    #expect(reader.readCount() == 2)
    try fixture.writeState(ids: ["two"])
    #expect(reader.readCount() == 1)
    try fixture.writeState(ids: [])
    #expect(reader.readCount() == 0)
    try unreadAuth(account: "a-different-account").write(to: fixture.authURL, options: .atomic)
    #expect(reader.readCount() == nil)
    try FileManager.default.removeItem(at: fixture.authURL)
    #expect(reader.readCount() == nil)
}

@Test
func unreadCountInvalidatesWhenArchiveChangesAndFailsClosedOnDamagedFiles() throws {
    let fixture = try UnreadFixture()
    defer { fixture.remove() }
    try fixture.execute("insert into threads values ('one', 0)")
    try fixture.writeState(ids: ["one"])
    let reader = fixture.reader()
    #expect(reader.readCount() == 1)
    try fixture.execute("update threads set archived = 1")
    #expect(reader.readCount() == 0)
    try Data("not-json".utf8).write(to: fixture.globalURL, options: .atomic)
    #expect(reader.readCount() == nil)
    try fixture.writeState(ids: [])
    #expect(reader.readCount() == 0)
    try FileManager.default.removeItem(at: fixture.databaseURL)
    #expect(reader.readCount() == nil)
}

@Test
func pollingDeliversReadChangesEvenWithoutSessionEvents() async throws {
    let fixture = try UnreadFixture()
    defer { fixture.remove() }
    try fixture.execute("insert into threads values ('one', 0)")
    try fixture.writeState(ids: ["one"])
    let engine = PollingEngine(unreadStateReader: fixture.reader(), providers: [])
    #expect(await engine.pollOnce().unreadCodexThreadCount == 1)
    try fixture.writeState(ids: [])
    #expect(await engine.pollOnce().unreadCodexThreadCount == 0)
}

private func unreadAuth(account: String = "test-account") throws -> Data {
    struct Claims: Encodable {
        struct Identity: Encodable {
            let chatgpt_account_id: String
            let user_id = "test-user"
            let chatgpt_user_id = "legacy-user"
        }
        let identity: Identity
        enum CodingKeys: String, CodingKey {
            case identity = "https://api.openai.com/auth"
        }
    }
    struct Auth: Encodable {
        struct Tokens: Encodable {
            let access_token: String
            let account_id: String
        }
        let auth_mode = "chatgpt"
        let tokens: Tokens
    }
    let claims = try JSONEncoder().encode(Claims(identity: .init(chatgpt_account_id: account)))
    let payload = claims.base64EncodedString().replacingOccurrences(of: "=", with: "")
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    return try JSONEncoder().encode(Auth(tokens: .init(access_token: "header.\(payload).signature", account_id: account)))
}

private func unreadState(buckets: [String: [String: [String]]], version: Int = 1) throws -> Data {
    struct State: Encodable {
        struct ReadState: Encodable {
            let version: Int
            let unreadByIdentity: [String: [String: [String]]]
        }
        let readState: ReadState
        enum CodingKeys: String, CodingKey {
            case readState = "electron-thread-read-state-v1"
        }
    }
    return try JSONEncoder().encode(State(readState: .init(version: version, unreadByIdentity: buckets)))
}

private struct UnreadFixture {
    let root: URL
    var databaseURL: URL { root.appendingPathComponent("state.sqlite") }
    var authURL: URL { root.appendingPathComponent("auth.json") }
    var globalURL: URL { root.appendingPathComponent(".codex-global-state.json") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try unreadAuth().write(to: authURL)
        try execute("create table threads (id text, archived integer)")
    }

    func writeState(ids: [String]) throws {
        let identity = try #require(try CodexUnreadStateReader.identityKey(authData: unreadAuth()))
        try unreadState(buckets: [identity: [CodexUnreadStateReader.localExecutionHostKey: ids]])
            .write(to: globalURL, options: .atomic)
    }

    func reader() -> CodexUnreadStateReader {
        CodexUnreadStateReader(environment: AppEnvironment(
            codexHome: root, sessionIndexURL: root.appendingPathComponent("index.jsonl"),
            stateStoreURL: databaseURL, logsStoreURL: root.appendingPathComponent("logs.sqlite"),
            claudeHome: root, claudeProjectsDirectory: root,
            codeBuddySupportDirectory: root, codeBuddySessionsStoreURL: root,
            codeBuddyTodosDirectory: root, codeBuddyGenieHistoryDirectory: root, codeBuddyCLIURL: root
        ))
    }

    func execute(_ sql: String) throws {
        var database: OpaquePointer?
        #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        let connection = try #require(database)
        #expect(sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
