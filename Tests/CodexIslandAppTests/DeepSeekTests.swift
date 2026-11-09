import Foundation
import Testing

@testable import CodexIslandCore

private func decodeDeepSeek<T: Decodable>(_ value: String, as: T.Type) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(value.utf8))
}

private func deepSeekMaterial(
    running: Bool = false, pending: String = "[]", events: String,
    start: Double = 0
) throws -> ProviderSessionMaterial {
    let item = try decodeDeepSeek(
        #"{"sessionId":"session","updatedAt":1000,"agentAvailable":true,"running":false,"blank":false,"cwd":"/tmp"}"#,
        as: DeepSeekSession.self)
    let projection = try decodeDeepSeek(
        #"{"kind":"sequenced","asOfSeq":10,"values":{"title":"Test","turnOutline":[{"prompt":"Hello","response":"World"}]}}"#,
        as: DeepSeekProjection.self)
    let state = try decodeDeepSeek(
        "{\"cursor\":10,\"active\":true,\"running\":\(running),\"pendingInput\":\(pending)}",
        as: DeepSeekState.self)
    let history = try decodeDeepSeek(
        "{\"cursor\":10,\"records\":[\(events)]}", as: DeepSeekHistory.self)
    return DeepSeekSessionBuilder.build(
        item: item, projection: projection, state: state, history: history,
        monitoringStartedAt: Date(timeIntervalSince1970: start))
}

@Test func deepSeekOnlyExplicitTurnEndCompletes() throws {
    let message =
        #"{"event":{"type":"assistant/message","seq":1,"time":2000,"data":{"message":{"content":[{"type":"reasoning","text":"private"},{"type":"text","text":"Visible"}]}}}}"#
    let active = try deepSeekMaterial(running: true, events: message)
    #expect(active.event?.kind == .responseInProgress)
    #expect(active.assistantPreview?.text == "Visible")
    let idle = try deepSeekMaterial(events: message)
    #expect(idle.event?.kind == .responseInterrupted)
    let ended = try deepSeekMaterial(
        events: message
            + #",{"event":{"type":"turn/end","seq":2,"time":3000,"data":{"reason":{"kind":"completed"}}}}"#
    )
    #expect(ended.event?.kind == .taskCompleted)
    let historical = try deepSeekMaterial(
        events:
            #"{"event":{"type":"turn/end","seq":2,"time":3000,"data":{"reason":{"kind":"completed"}}}}"#,
        start: 10)
    #expect(historical.event?.shouldNotifyCompletion == false)
}

@Test func deepSeekToolResultAndPendingInputOverrideActivity() throws {
    let call =
        #"{"event":{"type":"tool/call","seq":1,"time":2000,"data":{"name":"shell","callId":"tool"}}}"#
    #expect(try deepSeekMaterial(running: true, events: call).event?.kind == .toolUpdated)
    let finished =
        call
        + #",{"event":{"type":"tool/result","seq":2,"time":3000,"data":{"message":{"toolCallId":"tool"}}}}"#
    #expect(try deepSeekMaterial(running: true, events: finished).event?.kind == .responseInProgress)
    let waiting = try deepSeekMaterial(running: true, pending: #"["approval"]"#, events: finished)
    #expect(waiting.event?.kind == .userInputRequested)
    let coordinator = SessionCoordinator()
    coordinator.apply(threadSnapshots: [waiting.threadSnapshot])
    coordinator.apply(logEvents: [try #require(waiting.event)])
    #expect(coordinator.pendingUserInput?.provider == .deepSeek)
    coordinator.consumeUserInputNotification(for: try #require(coordinator.pendingUserInput))
    #expect(coordinator.pendingUserInput == nil)
    let historical = try deepSeekMaterial(pending: #"["question"]"#, events: call, start: 100)
    coordinator.apply(logEvents: [try #require(historical.event)])
    #expect(coordinator.pendingUserInput == nil)
}

@Test func deepSeekQuestionsPreserveProviderAndValidateMultipleChoices() throws {
    let projection = try decodeDeepSeek(
        #"{"kind":"sequenced","values":{"userQuestions":{"active":[{"callId":"call","state":"open","questions":[{"id":"q","question":"Choose","multiSelect":true,"options":[{"label":"A"},{"label":"B"}]}]}]}}}"#,
        as: DeepSeekProjection.self)
    let request = try #require(DeepSeekClient.questions(sessionID: "s", projection: projection).first)
    #expect(request.provider == .deepSeek)
    #expect(request.validates(["q": #"{"selected":["A","B"],"custom":""}"#]))
    #expect(request.validates(["q": #"{"selected":[],"custom":"alternative"}"#]))
    #expect(!request.validates(["q": #"{"selected":["unknown"],"custom":""}"#]))
    #expect(!request.validates(["q": #"{"selected":[],"custom":" "}"#]))
    #expect(!request.validates(["q": "A"]))
}

@Test func deepSeekLaunchDiscoveryOnlyAcceptsLoopback() {
    #expect(DeepSeekTransport.launchURL(in: "http://evil.example:3080/?token=fake") == nil)
    #expect(DeepSeekTransport.launchURL(in: "http://127.0.0.1:99999/?token=fake") == nil)
    #expect(
        DeepSeekTransport.launchURL(
            in: "http://localhost:3080/?token=old\nhttp://127.0.0.1:3081/?token=new")?.port == 3081)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_DEEPSEEK_LIVE_TEST"] == "1"))
func deepSeekLivePassiveConnection() async throws {
    let transport = DeepSeekTransport()
    let list = try await transport.call(
        "session/list", arguments: DeepSeekListArguments(), returning: DeepSeekSessionList.self)
    #expect(!list.items.isEmpty)
    let events = DeepSeekEvents(transport: transport)
    try await events.connect()
    for _ in 0..<20 {
        if await events.isReady { break }
        try await Task.sleep(for: .milliseconds(100))
    }
    #expect(await events.isReady)
    try await Task.sleep(for: .seconds(6))
    #expect(await events.isReady)
    await events.close()
    let account = await DeepSeekAccountClient(transport: transport).refresh()
    #expect(account != .unavailable)
    let client = DeepSeekClient(transport: transport)
    let refresh = await client.refresh()
    #expect(refresh.isConnected)
    #expect(!refresh.poll.threadSnapshots.isEmpty)
    #expect(refresh.poll.logEvents.allSatisfy { !$0.shouldNotifyCompletion })
    await client.close()
}

@Test func deepSeekInterruptedNewTurnCannotReusePreviousCompletion() throws {
    let history =
        #"{"event":{"type":"turn/end","seq":1,"time":1000,"data":{"reason":{"kind":"completed"}}}},{"event":{"type":"turn/start","seq":2,"time":2000,"data":{}}}"#
    #expect(try deepSeekMaterial(events: history).event?.kind == .responseInterrupted)
}

@Test func deepSeekBalanceUsesCurrencyPrecision() {
    let locale = Locale(identifier: "en_US_POSIX")
    #expect(DeepSeekBalancePresentation.amountText("14.1171576000000000", locale: locale) == "14.12")
    #expect(DeepSeekBalancePresentation.amountText("1.9181400800000000", locale: locale) == "1.92")
    #expect(DeepSeekBalancePresentation.amountText("0", locale: locale) == "0.00")
    #expect(DeepSeekBalancePresentation.amountText("unknown", locale: locale) == "unknown")
    let wallets = [
        DeepSeekBalance.Wallet(currency: "CNY", balance: "12.344"),
        DeepSeekBalance.Wallet(currency: "USD", balance: "3.5"),
    ]
    #expect(DeepSeekBalancePresentation.walletsText(wallets, locale: locale) == "12.34 CNY · 3.50 USD")
    #expect(DeepSeekBalancePresentation.walletsText([], locale: locale) == nil)
}

@Test func deepSeekStringTurnEndReasonStillCompletes() throws {
    let history =
        #"{"event":{"type":"turn/end","seq":1,"time":1000,"data":{"reason":"completed"}}}"#
    #expect(try deepSeekMaterial(events: history).event?.kind == .taskCompleted)
}

@Test func deepSeekUnfamiliarEventPayloadDoesNotAbortHistory() throws {
    let history =
        #"{"event":{"type":"turn/end","seq":1,"time":1000,"data":{"reason":42,"message":"text","name":7}}},{"event":{"type":"turn/start","seq":2,"time":2000}}"#
    let material = try deepSeekMaterial(events: history)
    #expect(material.threadSnapshot.threadID == "session")
    #expect(material.event?.kind == .responseInterrupted)
}

@Test func deepSeekNewTurnDoesNotReuseInterruptedTool() throws {
    let history =
        #"{"event":{"type":"tool/call","seq":1,"time":1000,"data":{"name":"shell","callId":"old"}}},{"event":{"type":"turn/start","seq":2,"time":2000,"data":{}}}"#
    let material = try deepSeekMaterial(running: true, events: history)
    #expect(material.event?.kind == .responseInProgress)
    #expect(material.event?.toolName == nil)
}
