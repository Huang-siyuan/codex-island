import Foundation

public struct DeepSeekMultipleAnswer: Codable, Sendable {
    public var selected: [String]
    public var custom: String
    public init(selected: [String] = [], custom: String = "") {
        self.selected = selected
        self.custom = custom
    }
}

/// Passive reads never activate/resume an Agent. Only an explicit answer invokes a mutation.
public actor DeepSeekClient {
    private let transport: DeepSeekTransport
    private var monitoringStartedAt: Date
    private let liveEvents: DeepSeekEvents
    private var lastRefreshAt = Date.distantPast
    private var cached: DeepSeekRefresh?
    private var details: [String: Detail] = [:]
    private var trackedIDs: Set<String> = []
    private var pendingCallIDs: [String: [String]] = [:]
    private var lastEvents: [String: CodexLogEvent] = [:]
    private let sessionLimit = 6

    private struct Detail {
        let cursor: Int
        let projection: DeepSeekProjection
        let history: DeepSeekHistory
    }

    public init(
        transport: DeepSeekTransport = DeepSeekTransport(), monitoringStartedAt: Date = Date()
    ) {
        self.transport = transport
        self.liveEvents = DeepSeekEvents(transport: transport)
        self.monitoringStartedAt = monitoringStartedAt
    }

    public func refresh(now: Date = Date()) async -> DeepSeekRefresh {
        if let cached, now.timeIntervalSince(lastRefreshAt) < 2 {
            return DeepSeekRefresh(
                poll: .init(
                    provider: .deepSeek, threadSnapshots: cached.poll.threadSnapshots,
                    logEvents: [], messagePreviews: []),
                questions: cached.questions, usage: cached.usage, isConnected: cached.isConnected)
        }
        lastRefreshAt = now
        do {
            let list = try await transport.call(
                "session/list", arguments: DeepSeekListArguments(), returning: DeepSeekSessionList.self)
            try await liveEvents.connect()
            let visible = list.items.filter { !$0.blank }.sorted {
                if $0.running != $1.running { return $0.running }
                return $0.updatedAt > $1.updatedAt
            }
            var snapshots: [ThreadSnapshot] = []
            var events: [CodexLogEvent] = []
            var previews: [SessionMessagePreview] = []
            var questions: [CodexQuestionRequest] = []
            var usage: [DeepSeekUsageSummary] = []
            for (index, item) in visible.enumerated() {
                let id = item.sessionId
                var projection = item.projections
                if index < sessionLimit || item.running
                    || !(item.projections?.values.userQuestions?.active.isEmpty ?? true)
                {
                    let state = try await transport.call(
                        "session/state",
                        arguments: DeepSeekRequestArguments(request: DeepSeekSessionRequest(sessionId: id)),
                        returning: DeepSeekState.self)
                    if details[id]?.cursor != state.cursor {
                        async let projected = transport.call(
                            "session/projections",
                            arguments: DeepSeekRequestArguments(request: DeepSeekSessionRequest(sessionId: id)),
                            returning: DeepSeekProjection.self)
                        async let history = transport.call(
                            "session/events",
                            arguments: DeepSeekRequestArguments(
                                request: DeepSeekHistoryRequest(address: .init(sessionId: id))),
                            returning: DeepSeekHistory.self)
                        let detail = try await Detail(
                            cursor: state.cursor, projection: projected, history: history)
                        guard detail.projection.kind == "sequenced" else { continue }
                        details[id] = detail
                    }
                    guard let detail = details[id] else { continue }
                    projection = detail.projection
                    let material = DeepSeekSessionBuilder.build(
                        item: item, projection: detail.projection, state: state,
                        history: detail.history, monitoringStartedAt: monitoringStartedAt)
                    snapshots.append(material.threadSnapshot)
                    previews.append(
                        contentsOf: [material.userPreview, material.assistantPreview].compactMap { $0 })
                    let callIDs =
                        detail.projection.values.userQuestions?.active.map(\.callId).sorted()
                        ?? state.pendingInput.sorted()
                    if let event = material.event {
                        let samePendingRequest =
                            event.kind == .userInputRequested && lastEvents[id]?.kind == .userInputRequested
                            && pendingCallIDs[id] == callIDs
                        if event != lastEvents[id], !samePendingRequest {
                            events.append(event)
                            lastEvents[id] = event
                        } else if !trackedIDs.contains(id) {
                            // Reintroduce an evicted card without replaying its already-seen notification.
                            events.append(
                                CodexLogEvent(
                                    provider: event.provider, threadID: event.threadID, kind: event.kind,
                                    toolName: event.toolName, summary: event.summary, timestamp: event.timestamp,
                                    shouldNotifyCompletion: false))
                        }
                        pendingCallIDs[id] = event.kind == .userInputRequested ? callIDs : nil
                    }
                    questions.append(contentsOf: Self.questions(sessionID: id, projection: detail.projection))
                }
                if let tokens = projection?.values.tokenUsage {
                    usage.append(
                        .init(
                            id: id, title: projection?.values.title ?? "DeepSeek Harness", tokens: tokens,
                            contextTokens: projection?.values.contextPressure?.projectedTokens,
                            contextWindow: projection?.values.contextPressure?.contextWindow))
                }
            }
            trackedIDs = Set(snapshots.map(\.threadID))
            let ids = Set(visible.map(\.sessionId))
            details = details.filter { ids.contains($0.key) }
            lastEvents = lastEvents.filter { ids.contains($0.key) }
            pendingCallIDs = pendingCallIDs.filter { ids.contains($0.key) }
            let result = DeepSeekRefresh(
                poll: .init(
                    provider: .deepSeek, threadSnapshots: snapshots, logEvents: events,
                    messagePreviews: previews), questions: questions, usage: usage, isConnected: true)
            cached = result
            return result
        } catch {
            // A stopped/restarted host is not evidence that any running turn completed.
            // Clear active sessions/questions instead of leaving actionable stale requests.
            let result = DeepSeekRefresh(
                poll: .init(provider: .deepSeek, threadSnapshots: [], logEvents: [], messagePreviews: []),
                questions: [], usage: cached?.usage ?? [], isConnected: false)
            cached = result
            trackedIDs.removeAll()
            details.removeAll()
            lastEvents.removeAll()
            pendingCallIDs.removeAll()
            monitoringStartedAt = now
            await liveEvents.close()
            return result
        }
    }

    public func answer(_ request: CodexQuestionRequest, answers: [String: String]) async throws {
        guard request.provider == .deepSeek, request.validates(answers),
            let callID = request.requestID.string
        else {
            throw DeepSeekError.invalidResponse
        }
        let projection = try await transport.call(
            "session/projections",
            arguments: DeepSeekRequestArguments(
                request: DeepSeekSessionRequest(sessionId: request.threadID)),
            returning: DeepSeekProjection.self)
        guard Self.questions(sessionID: request.threadID, projection: projection).contains(request)
        else {
            throw DeepSeekError.rejected
        }
        let values = try request.questions.map { question -> AnswerArguments.Batch.Answer in
            let raw = answers[question.id] ?? ""
            if question.multiSelect == true {
                let value = try JSONDecoder().decode(DeepSeekMultipleAnswer.self, from: Data(raw.utf8))
                return .init(
                    id: question.id, selected: value.selected,
                    custom: value.custom.isEmpty ? nil : value.custom)
            }
            let selected = (question.options ?? []).contains { $0.label == raw }
            return .init(id: question.id, selected: selected ? [raw] : [], custom: selected ? nil : raw)
        }
        let batch = AnswerArguments.Batch(answers: values)
        let call = projection.values.userQuestions?.active.first { $0.callId == callID }
        if call?.state == "continued" {
            let accepted = try await transport.call(
                "userQuestions/answer",
                arguments: AnswerArguments(agent: request.threadID, callId: callID, answer: batch),
                returning: Bool.self)
            guard accepted else { throw DeepSeekError.rejected }
        } else {
            try await liveEvents.answer(sessionID: request.threadID, callID: callID, value: batch)
        }
        // RPC acceptance is not proof that the question disappeared. Never auto-retry a write.
        for _ in 0..<10 {
            let updated = try await transport.call(
                "session/projections",
                arguments: DeepSeekRequestArguments(
                    request: DeepSeekSessionRequest(sessionId: request.threadID)),
                returning: DeepSeekProjection.self)
            if !(updated.values.userQuestions?.active.contains { $0.callId == callID } ?? false) {
                lastRefreshAt = .distantPast
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw DeepSeekError.rejected
    }

    public func close() async { await liveEvents.close() }

    static func questions(sessionID: String, projection: DeepSeekProjection) -> [CodexQuestionRequest] {
        (projection.values.userQuestions?.active ?? []).map { call in
            let questions = call.questions.map { question in
                CodexQuestion(
                    id: question.id, header: question.header ?? "DeepSeek Harness",
                    question: [question.question, question.detail].compactMap { $0 }.joined(separator: "\n"),
                    isOther: true, isSecret: false,
                    options: question.options?.map {
                        .init(label: $0.label, description: $0.description ?? "")
                    },
                    multiSelect: question.multiSelect)
            }
            return CodexQuestionRequest(
                provider: .deepSeek, threadID: sessionID, requestID: .string(call.callId),
                ownerID: "deepseek-harness", questions: questions)
        }
    }
}

private struct AnswerArguments: Encodable, Sendable {
    let agent: String
    let callId: String
    let answer: Batch
    struct Batch: Encodable, Sendable {
        let answers: [Answer]
        struct Answer: Encodable, Sendable {
            let id: String
            let selected: [String]
            let custom: String?
        }
    }
}

struct DeepSeekSessionBuilder {
    static func build(
        item: DeepSeekSession, projection: DeepSeekProjection, state: DeepSeekState,
        history: DeepSeekHistory, monitoringStartedAt: Date
    ) -> ProviderSessionMaterial {
        let records = history.records.map(\.event).sorted { $0.seq < $1.seq }
        let latest = records.last
        let timestamp =
            latest.map { Date(timeIntervalSince1970: $0.time / 1000) }
            ?? Date(timeIntervalSince1970: item.updatedAt / 1000)
        let outline = projection.values.turnOutline?.last
        let title = projection.values.title ?? outline?.prompt ?? "DeepSeek Harness"
        let snapshot = ThreadSnapshot(
            provider: .deepSeek, threadID: item.sessionId,
            title: SessionPreviewTextSanitizer.sanitize(title, previewLimit: 90),
            source: "deepseek-harness",
            cwd: projection.values.workingDirectory ?? item.cwd, updatedAt: timestamp,
            firstUserMessage: outline?.prompt)
        func preview(_ text: String?, author: SessionMessagePreview.Author) -> SessionMessagePreview? {
            guard let text, !text.isEmpty else { return nil }
            return .init(
                provider: .deepSeek, threadID: item.sessionId, author: author,
                text: SessionPreviewTextSanitizer.sanitize(text, previewLimit: 600), timestamp: timestamp)
        }
        let lastAssistant = records.last { $0.type == "assistant/message" }
        let assistant = lastAssistant?.data.message?.content?.filter { $0.type == "text" }.compactMap(
            \.text
        ).joined(separator: "\n")
        let lastStart = records.last { $0.type == "turn/start" }?.seq ?? -1
        let completedTools = Set(
            records.filter { $0.type == "tool/result" }.compactMap { $0.data.message?.toolCallId })
        let lastTool = records.last {
            $0.type == "tool/call" && $0.seq > lastStart
                && ($0.data.callId.map { !completedTools.contains($0) } ?? true)
        }
        let terminal = records.last { $0.type == "turn/end" && $0.seq > lastStart }
        var kind: CodexLogEventKind?
        var eventTime = timestamp
        var tool: String?
        let waiting =
            !state.pendingInput.isEmpty
            || (projection.values.userQuestions?.active.contains { $0.state == "open" } ?? false)
        if waiting {
            kind = .userInputRequested
        } else if state.running {
            tool = lastTool?.data.name
            kind = tool == nil ? .responseInProgress : .toolUpdated
        } else if let terminal {
            eventTime = Date(timeIntervalSince1970: terminal.time / 1000)
            kind = terminal.data.reason?.kind == "completed" ? .taskCompleted : .responseInterrupted
        } else {
            kind = .responseInterrupted
        }
        // Historical finishes must render without replaying completion/input sounds on launch.
        let notify = eventTime >= monitoringStartedAt
        let event = kind.map {
            CodexLogEvent(
                provider: .deepSeek, threadID: item.sessionId, kind: $0,
                toolName: tool, summary: tool ?? ($0 == .taskCompleted ? "Completed" : "DeepSeek Harness"),
                timestamp: eventTime, shouldNotifyCompletion: notify)
        }
        return .init(
            threadSnapshot: snapshot, userPreview: preview(outline?.prompt, author: .user),
            assistantPreview: preview(
                assistant?.isEmpty == false ? assistant : outline?.response, author: .assistant),
            event: event)
    }
}
