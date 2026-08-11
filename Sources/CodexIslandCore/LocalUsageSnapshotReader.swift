import Foundation

public struct LocalUsageDay: Sendable, Equatable, Identifiable {
    public let dayKey: String
    public let inputTokens: Int
    public let cachedInputTokens: Int
    public let outputTokens: Int
    public let totalTokens: Int
    public let agentTimeMS: Int
    public let agentRuns: Int

    public init(
        dayKey: String,
        inputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int,
        totalTokens: Int,
        agentTimeMS: Int,
        agentRuns: Int
    ) {
        self.dayKey = dayKey
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.agentTimeMS = agentTimeMS
        self.agentRuns = agentRuns
    }

    public var id: String { dayKey }
}

public struct LocalUsageTotals: Sendable, Equatable {
    public let last7DaysTokens: Int
    public let last30DaysTokens: Int
    public let averageDailyTokens: Int
    public let cacheHitRatePercent: Double
    public let peakDay: String?
    public let peakDayTokens: Int

    public init(
        last7DaysTokens: Int,
        last30DaysTokens: Int,
        averageDailyTokens: Int,
        cacheHitRatePercent: Double,
        peakDay: String?,
        peakDayTokens: Int
    ) {
        self.last7DaysTokens = last7DaysTokens
        self.last30DaysTokens = last30DaysTokens
        self.averageDailyTokens = averageDailyTokens
        self.cacheHitRatePercent = cacheHitRatePercent
        self.peakDay = peakDay
        self.peakDayTokens = peakDayTokens
    }
}

public struct LocalUsageModel: Sendable, Equatable, Identifiable {
    public let model: String
    public let tokens: Int
    public let sharePercent: Double

    public init(model: String, tokens: Int, sharePercent: Double) {
        self.model = model
        self.tokens = tokens
        self.sharePercent = sharePercent
    }

    public var id: String { model }
}

public struct LocalUsageSnapshot: Sendable, Equatable {
    public let updatedAt: Date
    public let days: [LocalUsageDay]
    public let totals: LocalUsageTotals
    public let topModels: [LocalUsageModel]

    public init(
        updatedAt: Date,
        days: [LocalUsageDay],
        totals: LocalUsageTotals,
        topModels: [LocalUsageModel]
    ) {
        self.updatedAt = updatedAt
        self.days = days
        self.totals = totals
        self.topModels = topModels
    }

    public static func empty(days: Int = 30, now: Date = Date()) -> LocalUsageSnapshot {
        let normalizedDays = max(1, min(days, 90))
        let calendar = Calendar.autoupdatingCurrent
        let dayKeys = (0..<normalizedDays).compactMap { offset -> String? in
            guard let date = calendar.date(byAdding: .day, value: -((normalizedDays - 1) - offset), to: now) else {
                return nil
            }
            return LocalUsageSnapshotReader.dayKeyFormatter.string(from: date)
        }
        let dayEntries = dayKeys.map {
            LocalUsageDay(
                dayKey: $0,
                inputTokens: 0,
                cachedInputTokens: 0,
                outputTokens: 0,
                totalTokens: 0,
                agentTimeMS: 0,
                agentRuns: 0
            )
        }
        return LocalUsageSnapshot(
            updatedAt: now,
            days: dayEntries,
            totals: LocalUsageTotals(
                last7DaysTokens: 0,
                last30DaysTokens: 0,
                averageDailyTokens: 0,
                cacheHitRatePercent: 0,
                peakDay: nil,
                peakDayTokens: 0
            ),
            topModels: []
        )
    }
}

public final class LocalUsageSnapshotReader {
    private struct DailyTotals {
        var input: Int = 0
        var cached: Int = 0
        var output: Int = 0
        var agentTimeMS: Int = 0
        var agentRuns: Int = 0
    }

    private struct UsageTotals {
        var input: Int = 0
        var cached: Int = 0
        var output: Int = 0
    }

    private static let maxActivityGapMS = 2 * 60 * 1_000
    fileprivate static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private let fileManager: FileManager
    private let calendar: Calendar
    private let now: () -> Date
    private let sessionsRootsProvider: () -> [URL]
    private let fractionalISO8601Formatter: ISO8601DateFormatter
    private let fallbackISO8601Formatter: ISO8601DateFormatter

    public init(
        environment: AppEnvironment = .default,
        fileManager: FileManager = .default,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init
    ) {
        let sessionsRoot = environment.codexHome.appendingPathComponent("sessions", isDirectory: true)
        self.fileManager = fileManager
        self.calendar = calendar
        self.now = now
        self.sessionsRootsProvider = { [sessionsRoot] in [sessionsRoot] }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        fractionalFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        self.fractionalISO8601Formatter = fractionalFormatter
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        fallbackFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        self.fallbackISO8601Formatter = fallbackFormatter
    }

    init(
        sessionsRoots: [URL],
        fileManager: FileManager = .default,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.now = now
        self.sessionsRootsProvider = { sessionsRoots }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        fractionalFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        self.fractionalISO8601Formatter = fractionalFormatter
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        fallbackFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        self.fallbackISO8601Formatter = fallbackFormatter
    }

    public func readSnapshot(days: Int = 30) -> LocalUsageSnapshot {
        let normalizedDays = max(1, min(days, 90))
        let referenceDate = now()
        let dayKeys = makeDayKeys(days: normalizedDays, referenceDate: referenceDate)
        var daily = Dictionary(uniqueKeysWithValues: dayKeys.map { ($0, DailyTotals()) })
        var modelTotals: [String: Int] = [:]

        let sessionRoots = Array(Set(sessionsRootsProvider().map(\.path)))
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            .filter { fileManager.fileExists(atPath: $0.path) }

        for root in sessionRoots {
            scan(root: root, dayKeys: dayKeys, daily: &daily, modelTotals: &modelTotals)
        }

        return buildSnapshot(
            updatedAt: referenceDate,
            dayKeys: dayKeys,
            daily: daily,
            modelTotals: modelTotals
        )
    }

    private func scan(
        root: URL,
        dayKeys: [String],
        daily: inout [String: DailyTotals],
        modelTotals: inout [String: Int]
    ) {
        for dayKey in dayKeys {
            let dayDirectory = directoryURL(for: dayKey, under: root)
            guard let fileURLs = try? fileManager.contentsOfDirectory(
                at: dayDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for fileURL in fileURLs where fileURL.pathExtension == "jsonl" {
                scan(fileURL: fileURL, daily: &daily, modelTotals: &modelTotals)
            }
        }
    }

    private func scan(
        fileURL: URL,
        daily: inout [String: DailyTotals],
        modelTotals: inout [String: Int]
    ) {
        guard let transcript = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return
        }

        var previousTotals = UsageTotals()
        var currentModel: String?
        var lastActivityMS: Int64?
        var seenRuns: Set<Int64> = []

        for rawLine in transcript.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard line.utf8.count <= 512_000,
                  let data = line.data(using: .utf8),
                  let rawObject = try? JSONSerialization.jsonObject(with: data),
                  let object = rawObject as? [String: Any] else {
                continue
            }

            let entryType = (object["type"] as? String) ?? ""
            if entryType == "turn_context" {
                currentModel = extractModel(fromTurnContext: object) ?? currentModel
                continue
            }

            if entryType == "session_meta" {
                continue
            }

            if entryType == "event_msg" || entryType.isEmpty {
                let payload = object["payload"] as? [String: Any]
                let payloadType = payload?["type"] as? String

                if payloadType == "agent_message" {
                    guard let timestampMS = readTimestampMS(from: object) else {
                        continue
                    }
                    registerAgentRun(timestampMS, daily: &daily, seenRuns: &seenRuns)
                    trackActivity(timestampMS, daily: &daily, lastActivityMS: &lastActivityMS)
                    continue
                }

                if payloadType == "agent_reasoning" {
                    guard let timestampMS = readTimestampMS(from: object) else {
                        continue
                    }
                    trackActivity(timestampMS, daily: &daily, lastActivityMS: &lastActivityMS)
                    continue
                }

                guard payloadType == "token_count",
                      let info = payload?["info"] as? [String: Any] else {
                    continue
                }

                let usage = extractUsage(from: info)
                guard let usage else {
                    continue
                }

                var delta = UsageTotals(
                    input: usage.input,
                    cached: usage.cached,
                    output: usage.output
                )

                if usage.usedTotal {
                    delta = UsageTotals(
                        input: max(0, usage.input - previousTotals.input),
                        cached: max(0, usage.cached - previousTotals.cached),
                        output: max(0, usage.output - previousTotals.output)
                    )
                    previousTotals = UsageTotals(
                        input: usage.input,
                        cached: usage.cached,
                        output: usage.output
                    )
                } else {
                    previousTotals.input += delta.input
                    previousTotals.cached += delta.cached
                    previousTotals.output += delta.output
                }

                guard delta.input > 0 || delta.cached > 0 || delta.output > 0 else {
                    continue
                }

                guard let timestampMS = readTimestampMS(from: object),
                      let dayKey = dayKey(forTimestampMS: timestampMS),
                      var entry = daily[dayKey] else {
                    continue
                }

                let cached = min(delta.cached, delta.input)
                entry.input += delta.input
                entry.cached += cached
                entry.output += delta.output
                daily[dayKey] = entry

                let modelName = currentModel
                    ?? extractModel(fromTokenCount: object)
                    ?? "unknown"
                modelTotals[modelName, default: 0] += delta.input + delta.output

                trackActivity(timestampMS, daily: &daily, lastActivityMS: &lastActivityMS)
                continue
            }

            guard entryType == "response_item",
                  let payload = object["payload"] as? [String: Any] else {
                continue
            }

            let role = payload["role"] as? String
            let payloadType = payload["type"] as? String
            guard let timestampMS = readTimestampMS(from: object) else {
                continue
            }

            if role == "assistant" {
                registerAgentRun(timestampMS, daily: &daily, seenRuns: &seenRuns)
                trackActivity(timestampMS, daily: &daily, lastActivityMS: &lastActivityMS)
                continue
            }

            if payloadType != "message" {
                trackActivity(timestampMS, daily: &daily, lastActivityMS: &lastActivityMS)
            }
        }
    }

    private func buildSnapshot(
        updatedAt: Date,
        dayKeys: [String],
        daily: [String: DailyTotals],
        modelTotals: [String: Int]
    ) -> LocalUsageSnapshot {
        var days: [LocalUsageDay] = []
        var totalTokens = 0

        for dayKey in dayKeys {
            let totals = daily[dayKey] ?? DailyTotals()
            let total = totals.input + totals.output
            totalTokens += total
            days.append(
                LocalUsageDay(
                    dayKey: dayKey,
                    inputTokens: totals.input,
                    cachedInputTokens: totals.cached,
                    outputTokens: totals.output,
                    totalTokens: total,
                    agentTimeMS: totals.agentTimeMS,
                    agentRuns: totals.agentRuns
                )
            )
        }

        let last7Days = Array(days.suffix(7))
        let last7Tokens = last7Days.reduce(0) { $0 + $1.totalTokens }
        let last7Input = last7Days.reduce(0) { $0 + $1.inputTokens }
        let last7Cached = last7Days.reduce(0) { $0 + $1.cachedInputTokens }
        let averageDailyTokens = last7Days.isEmpty ? 0 : Int((Double(last7Tokens) / Double(last7Days.count)).rounded())
        let cacheHitRatePercent = last7Input == 0 ? 0 : ((Double(last7Cached) / Double(last7Input)) * 1000).rounded() / 10
        let peakDay = days.max { $0.totalTokens < $1.totalTokens }
        let peakDescriptor = peakDay?.totalTokens ?? 0 > 0 ? peakDay : nil

        let topModels = modelTotals
            .filter { !$0.key.isEmpty && $0.key != "unknown" && $0.value > 0 }
            .map { key, value in
                LocalUsageModel(
                    model: key,
                    tokens: value,
                    sharePercent: totalTokens == 0 ? 0 : ((Double(value) / Double(totalTokens)) * 1000).rounded() / 10
                )
            }
            .sorted { lhs, rhs in
                if lhs.tokens == rhs.tokens {
                    return lhs.model < rhs.model
                }
                return lhs.tokens > rhs.tokens
            }
            .prefix(4)

        return LocalUsageSnapshot(
            updatedAt: updatedAt,
            days: days,
            totals: LocalUsageTotals(
                last7DaysTokens: last7Tokens,
                last30DaysTokens: totalTokens,
                averageDailyTokens: averageDailyTokens,
                cacheHitRatePercent: cacheHitRatePercent,
                peakDay: peakDescriptor?.dayKey,
                peakDayTokens: peakDescriptor?.totalTokens ?? 0
            ),
            topModels: Array(topModels)
        )
    }

    private func makeDayKeys(days: Int, referenceDate: Date) -> [String] {
        let startOfToday = calendar.startOfDay(for: referenceDate)
        return (0..<days).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -((days - 1) - offset), to: startOfToday) else {
                return nil
            }
            return Self.dayKeyFormatter.string(from: date)
        }
    }

    private func directoryURL(for dayKey: String, under root: URL) -> URL {
        let parts = dayKey.split(separator: "-")
        guard parts.count == 3 else {
            return root
        }
        return root
            .appendingPathComponent(String(parts[0]), isDirectory: true)
            .appendingPathComponent(String(parts[1]), isDirectory: true)
            .appendingPathComponent(String(parts[2]), isDirectory: true)
    }

    private func registerAgentRun(
        _ timestampMS: Int64,
        daily: inout [String: DailyTotals],
        seenRuns: inout Set<Int64>
    ) {
        guard seenRuns.insert(timestampMS).inserted,
              let dayKey = dayKey(forTimestampMS: timestampMS),
              var entry = daily[dayKey] else {
            return
        }
        entry.agentRuns += 1
        daily[dayKey] = entry
    }

    private func trackActivity(
        _ timestampMS: Int64,
        daily: inout [String: DailyTotals],
        lastActivityMS: inout Int64?
    ) {
        defer { lastActivityMS = timestampMS }
        guard let previousTimestampMS = lastActivityMS else {
            return
        }

        let delta = timestampMS - previousTimestampMS
        guard delta > 0,
              delta <= Int64(Self.maxActivityGapMS),
              let dayKey = dayKey(forTimestampMS: timestampMS),
              var entry = daily[dayKey] else {
            return
        }

        entry.agentTimeMS += Int(delta)
        daily[dayKey] = entry
    }

    private func dayKey(forTimestampMS timestampMS: Int64) -> String? {
        let seconds = TimeInterval(timestampMS) / 1_000
        let date = Date(timeIntervalSince1970: seconds)
        return Self.dayKeyFormatter.string(from: date)
    }

    private func extractUsage(from info: [String: Any]) -> (input: Int, cached: Int, output: Int, usedTotal: Bool)? {
        if let totalUsage = findUsageDictionary(in: info, keys: ["total_token_usage", "totalTokenUsage"]) {
            return (
                readInt(from: totalUsage, keys: ["input_tokens", "inputTokens"]),
                readInt(from: totalUsage, keys: ["cached_input_tokens", "cache_read_input_tokens", "cachedInputTokens", "cacheReadInputTokens"]),
                readInt(from: totalUsage, keys: ["output_tokens", "outputTokens"]),
                true
            )
        }

        if let lastUsage = findUsageDictionary(in: info, keys: ["last_token_usage", "lastTokenUsage"]) {
            return (
                readInt(from: lastUsage, keys: ["input_tokens", "inputTokens"]),
                readInt(from: lastUsage, keys: ["cached_input_tokens", "cache_read_input_tokens", "cachedInputTokens", "cacheReadInputTokens"]),
                readInt(from: lastUsage, keys: ["output_tokens", "outputTokens"]),
                false
            )
        }

        return nil
    }

    private func extractModel(fromTurnContext object: [String: Any]) -> String? {
        guard let payload = object["payload"] as? [String: Any] else {
            return nil
        }
        if let model = payload["model"] as? String, !model.isEmpty {
            return model
        }
        if let info = payload["info"] as? [String: Any],
           let model = info["model"] as? String,
           !model.isEmpty {
            return model
        }
        return nil
    }

    private func extractModel(fromTokenCount object: [String: Any]) -> String? {
        guard let payload = object["payload"] as? [String: Any] else {
            return nil
        }
        if let info = payload["info"] as? [String: Any] {
            if let model = info["model"] as? String, !model.isEmpty {
                return model
            }
            if let model = info["model_name"] as? String, !model.isEmpty {
                return model
            }
        }
        if let model = payload["model"] as? String, !model.isEmpty {
            return model
        }
        if let model = object["model"] as? String, !model.isEmpty {
            return model
        }
        return nil
    }

    private func findUsageDictionary(in info: [String: Any], keys: [String]) -> [String: Any]? {
        for key in keys {
            if let value = info[key] as? [String: Any] {
                return value
            }
        }
        return nil
    }

    private func readInt(from dictionary: [String: Any], keys: [String]) -> Int {
        for key in keys {
            if let intValue = dictionary[key] as? Int {
                return intValue
            }
            if let int64Value = dictionary[key] as? Int64 {
                return Int(int64Value)
            }
            if let doubleValue = dictionary[key] as? Double {
                return Int(doubleValue)
            }
            if let stringValue = dictionary[key] as? String, let intValue = Int(stringValue) {
                return intValue
            }
            if let numberValue = dictionary[key] as? NSNumber {
                return numberValue.intValue
            }
        }
        return 0
    }

    private func readTimestampMS(from object: [String: Any]) -> Int64? {
        guard let rawTimestamp = object["timestamp"] else {
            return nil
        }

        if let text = rawTimestamp as? String {
            if let date = fractionalISO8601Formatter.date(from: text) ?? fallbackISO8601Formatter.date(from: text) {
                return Int64((date.timeIntervalSince1970 * 1_000).rounded())
            }
            return nil
        }

        if let intValue = rawTimestamp as? Int64 {
            return intValue < 1_000_000_000_000 ? intValue * 1_000 : intValue
        }
        if let intValue = rawTimestamp as? Int {
            let timestamp = Int64(intValue)
            return timestamp < 1_000_000_000_000 ? timestamp * 1_000 : timestamp
        }
        if let doubleValue = rawTimestamp as? Double {
            let timestamp = Int64(doubleValue)
            return timestamp < 1_000_000_000_000 ? timestamp * 1_000 : timestamp
        }
        if let numberValue = rawTimestamp as? NSNumber {
            let timestamp = numberValue.int64Value
            return timestamp < 1_000_000_000_000 ? timestamp * 1_000 : timestamp
        }
        return nil
    }
}
