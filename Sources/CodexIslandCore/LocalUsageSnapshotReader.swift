import Foundation

public actor UsageSnapshotLoader {
    private let reader: LocalUsageSnapshotReader
    private let refreshInterval: TimeInterval
    private let cacheURL: URL
    private var cachedSnapshot: LocalUsageSnapshot?
    private var lastRefreshAt: Date?

    public init(
        reader: LocalUsageSnapshotReader = LocalUsageSnapshotReader(),
        refreshInterval: TimeInterval = 1_800,
        cacheURL: URL? = nil
    ) {
        self.reader = reader
        self.refreshInterval = refreshInterval
        self.cacheURL = cacheURL ?? FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0]
            .appendingPathComponent("CodexIsland", isDirectory: true)
            .appendingPathComponent("usage-snapshot.json")

        if let data = try? Data(contentsOf: self.cacheURL),
           let snapshot = try? JSONDecoder().decode(LocalUsageSnapshot.self, from: data),
           snapshot.schemaVersion == LocalUsageSnapshot.currentSchemaVersion {
            cachedSnapshot = snapshot
            lastRefreshAt = snapshot.updatedAt
        }
    }

    public func cached() -> LocalUsageSnapshot? {
        cachedSnapshot
    }

    public func needsRefreshForCurrentDay(
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        guard let lastRefreshAt else {
            return true
        }
        return !calendar.isDate(lastRefreshAt, inSameDayAs: now)
    }

    public func snapshot(now: Date = Date()) -> LocalUsageSnapshot {
        if let cachedSnapshot,
           let lastRefreshAt,
           now.timeIntervalSince(lastRefreshAt) < refreshInterval {
            return cachedSnapshot
        }

        let snapshot = reader.readSnapshot(days: 30)
        cachedSnapshot = snapshot
        lastRefreshAt = now
        persist(snapshot)
        return snapshot
    }

    private func persist(_ snapshot: LocalUsageSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            return
        }
        let directory = cacheURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }
}

public struct LocalUsageDay: Codable, Sendable, Equatable, Identifiable {
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

public struct LocalUsageTotals: Codable, Sendable, Equatable {
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

public struct LocalUsageModel: Codable, Sendable, Equatable, Identifiable {
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

public struct LocalUsageWorkspace: Codable, Sendable, Equatable, Identifiable {
    // A non-filesystem identity keeps topic sessions in one group without adding their temporary directories to the picker.
    public static let unassignedID = "codex-island:unassigned"

    public let path: String
    public let name: String
    public let days: [LocalUsageDay]
    public let totals: LocalUsageTotals
    public let topModels: [LocalUsageModel]

    public init(
        path: String,
        name: String,
        days: [LocalUsageDay],
        totals: LocalUsageTotals,
        topModels: [LocalUsageModel]
    ) {
        self.path = path
        self.name = name
        self.days = days
        self.totals = totals
        self.topModels = topModels
    }

    public var id: String { path }
    public var isUnassigned: Bool { id == Self.unassignedID }
}

public struct LocalUsageSnapshot: Codable, Sendable, Equatable {
    // Earlier snapshots excluded non-project sessions and must be rebuilt even within the refresh interval.
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let updatedAt: Date
    public let days: [LocalUsageDay]
    public let totals: LocalUsageTotals
    public let topModels: [LocalUsageModel]
    public let workspaces: [LocalUsageWorkspace]

    public init(
        updatedAt: Date,
        days: [LocalUsageDay],
        totals: LocalUsageTotals,
        topModels: [LocalUsageModel],
        workspaces: [LocalUsageWorkspace] = []
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.updatedAt = updatedAt
        self.days = days
        self.totals = totals
        self.topModels = topModels
        self.workspaces = workspaces
    }

    public func filtered(toWorkspaceID workspaceID: String?) -> LocalUsageSnapshot {
        guard let workspaceID,
              let workspace = workspaces.first(where: { $0.id == workspaceID }) else {
            return self
        }
        return LocalUsageSnapshot(
            updatedAt: updatedAt,
            days: workspace.days,
            totals: workspace.totals,
            topModels: workspace.topModels,
            workspaces: workspaces
        )
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
            topModels: [],
            workspaces: []
        )
    }
}

public final class LocalUsageSnapshotReader {
    // Usage events are small; large lines are usually images or tool payloads and must not enter JSON decoding.
    private static let maximumRelevantLineSize = 128_000
    private static let jsonTypePrefix = Array("\"type\":\"".utf8)
    private static let relevantEventTypes: [[UInt8]] = [
        Array("session_meta\"".utf8),
        Array("turn_context\"".utf8),
        Array("token_count\"".utf8),
        Array("agent_message\"".utf8),
        Array("agent_reasoning\"".utf8),
        Array("response_item\"".utf8),
    ]

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

    private struct ScanResult {
        let workspacePath: String?
        let daily: [String: DailyTotals]
        let modelTotals: [String: Int]
    }

    private struct ScanState {
        var daily: [String: DailyTotals]
        var modelTotals: [String: Int] = [:]
        var workspacePath: String?
        var previousTotals = UsageTotals()
        var currentModel: String?
        var lastActivityMS: Int64?
        var seenRuns: Set<Int64> = []

        var result: ScanResult {
            ScanResult(
                workspacePath: workspacePath,
                daily: daily,
                modelTotals: modelTotals
            )
        }
    }

    private struct FileScanCache {
        var fileSize: UInt64
        var modificationDate: Date?
        var endedWithNewline: Bool
        var state: ScanState
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
    private let savedWorkspaceRootsProvider: () -> [URL]?
    private let fractionalISO8601Formatter: ISO8601DateFormatter
    private let fallbackISO8601Formatter: ISO8601DateFormatter
    private var cachedDayKeys: [String] = []
    private var fileScanCache: [String: FileScanCache] = [:]
    private var scannedFilePaths: Set<String> = []

    public init(
        environment: AppEnvironment = .default,
        fileManager: FileManager = .default,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init
    ) {
        let sessionsRoot = environment.codexHome.appendingPathComponent("sessions", isDirectory: true)
        let globalStateURL = environment.codexHome.appendingPathComponent(".codex-global-state.json")
        self.fileManager = fileManager
        self.calendar = calendar
        self.now = now
        self.sessionsRootsProvider = { [sessionsRoot] in [sessionsRoot] }
        self.savedWorkspaceRootsProvider = {
            Self.readSavedWorkspaceRoots(from: globalStateURL, fileManager: fileManager)
        }
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
        savedWorkspaceRoots: [URL]? = nil,
        fileManager: FileManager = .default,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init
    ) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.now = now
        self.sessionsRootsProvider = { sessionsRoots }
        self.savedWorkspaceRootsProvider = { savedWorkspaceRoots }
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
        if cachedDayKeys != dayKeys {
            cachedDayKeys = dayKeys
            fileScanCache.removeAll(keepingCapacity: true)
        }
        scannedFilePaths.removeAll(keepingCapacity: true)
        var daily = Dictionary(uniqueKeysWithValues: dayKeys.map { ($0, DailyTotals()) })
        var modelTotals: [String: Int] = [:]
        var workspaceDaily: [String: [String: DailyTotals]] = [:]
        var workspaceModelTotals: [String: [String: Int]] = [:]
        let savedWorkspacePaths = savedWorkspaceRootsProvider().map(normalizedWorkspacePaths)

        // Saved roots define project groups, never which sessions contribute to overall usage.
        if let savedWorkspacePaths {
            for path in savedWorkspacePaths {
                workspaceDaily[path] = Dictionary(uniqueKeysWithValues: dayKeys.map { ($0, DailyTotals()) })
                workspaceModelTotals[path] = [:]
            }
        }

        let sessionRoots = Array(Set(sessionsRootsProvider().map(\.path)))
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            .filter { fileManager.fileExists(atPath: $0.path) }

        for root in sessionRoots {
            scan(
                root: root,
                dayKeys: dayKeys,
                daily: &daily,
                modelTotals: &modelTotals,
                workspaceDaily: &workspaceDaily,
                workspaceModelTotals: &workspaceModelTotals,
                savedWorkspacePaths: savedWorkspacePaths
            )
        }
        fileScanCache = fileScanCache.filter { scannedFilePaths.contains($0.key) }

        let workspaces: [LocalUsageWorkspace] = workspaceDaily.keys.map { path in
            let workspaceSnapshot = buildSnapshot(
                updatedAt: referenceDate,
                dayKeys: dayKeys,
                daily: workspaceDaily[path] ?? [:],
                modelTotals: workspaceModelTotals[path] ?? [:]
            )
            return LocalUsageWorkspace(
                path: path,
                name: path == LocalUsageWorkspace.unassignedID
                    ? "Topics / No project"
                    : URL(fileURLWithPath: path).lastPathComponent,
                days: workspaceSnapshot.days,
                totals: workspaceSnapshot.totals,
                topModels: workspaceSnapshot.topModels
            )
        }
        .sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return buildSnapshot(
            updatedAt: referenceDate,
            dayKeys: dayKeys,
            daily: daily,
            modelTotals: modelTotals,
            workspaces: workspaces
        )
    }

    private func scan(
        root: URL,
        dayKeys: [String],
        daily: inout [String: DailyTotals],
        modelTotals: inout [String: Int],
        workspaceDaily: inout [String: [String: DailyTotals]],
        workspaceModelTotals: inout [String: [String: Int]],
        savedWorkspacePaths: [String]?
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
                guard let result = scan(fileURL: fileURL, dayKeys: dayKeys) else {
                    continue
                }
                // Topic sessions and sessions with no cwd still contribute to every overall metric.
                merge(result.daily, into: &daily)
                merge(result.modelTotals, into: &modelTotals)

                let workspacePath: String?
                if let savedWorkspacePaths {
                    workspacePath = result.workspacePath.flatMap {
                        matchingWorkspaceRoot(for: $0, savedWorkspacePaths: savedWorkspacePaths)
                    }
                } else {
                    workspacePath = result.workspacePath
                }

                let groupID = workspacePath ?? LocalUsageWorkspace.unassignedID
                var scopedDaily = workspaceDaily[groupID]
                    ?? Dictionary(uniqueKeysWithValues: dayKeys.map { ($0, DailyTotals()) })
                var scopedModels = workspaceModelTotals[groupID] ?? [:]
                merge(result.daily, into: &scopedDaily)
                merge(result.modelTotals, into: &scopedModels)
                workspaceDaily[groupID] = scopedDaily
                workspaceModelTotals[groupID] = scopedModels
            }
        }
    }

    private func normalizedWorkspacePaths(_ roots: [URL]) -> [String] {
        Array(Set(roots.map { $0.standardizedFileURL.path }))
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
    }

    private func matchingWorkspaceRoot(for sessionPath: String, savedWorkspacePaths: [String]) -> String? {
        savedWorkspacePaths.first { rootPath in
            sessionPath == rootPath || sessionPath.hasPrefix(rootPath + "/")
        }
    }

    private static func readSavedWorkspaceRoots(from url: URL, fileManager: FileManager) -> [URL] {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let paths = object["electron-saved-workspace-roots"] as? [String] else {
            return []
        }

        return paths.compactMap { rawPath in
            let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else {
                return nil
            }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
    }

    private func scan(
        fileURL: URL,
        dayKeys: [String]
    ) -> ScanResult? {
        let path = fileURL.path
        scannedFilePaths.insert(path)
        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              let fileSizeNumber = attributes[.size] as? NSNumber else {
            return nil
        }
        let fileSize = fileSizeNumber.uint64Value
        let modificationDate = attributes[.modificationDate] as? Date

        let cached = fileScanCache[path]
        if let cached,
           cached.fileSize == fileSize,
           cached.modificationDate == modificationDate {
            return cached.state.result
        }

        let canContinue = cached.map {
            fileSize > $0.fileSize && $0.endedWithNewline
        } ?? false
        var state: ScanState
        let startOffset: UInt64
        if canContinue, let cached {
            state = cached.state
            startOffset = cached.fileSize
        } else {
            state = ScanState(daily: Dictionary(uniqueKeysWithValues: dayKeys.map { ($0, DailyTotals()) }))
            startOffset = 0
        }

        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: startOffset)
        } catch {
            return nil
        }

        var pending = Data()
        var discardingOversizedLine = false
        var endedWithNewline = startOffset > 0
        var reachedEnd = false
        while !reachedEnd {
            autoreleasepool {
                guard let chunk = try? handle.read(upToCount: 1_048_576),
                      !chunk.isEmpty else {
                    reachedEnd = true
                    return
                }
                var segmentStart = chunk.startIndex
                while let newline = chunk[segmentStart...].firstIndex(of: 0x0A) {
                    let segment = chunk[segmentStart..<newline]
                    if !discardingOversizedLine,
                       pending.count + segment.count <= Self.maximumRelevantLineSize {
                        pending.append(segment)
                        process(line: pending[pending.startIndex..<pending.endIndex], state: &state)
                    }
                    pending.removeAll(keepingCapacity: true)
                    discardingOversizedLine = false
                    segmentStart = chunk.index(after: newline)
                    endedWithNewline = true
                }

                if segmentStart < chunk.endIndex {
                    endedWithNewline = false
                    guard !discardingOversizedLine else {
                        return
                    }
                    let segment = chunk[segmentStart..<chunk.endIndex]
                    if pending.count + segment.count <= Self.maximumRelevantLineSize {
                        pending.append(segment)
                    } else {
                        pending.removeAll(keepingCapacity: true)
                        discardingOversizedLine = true
                    }
                }
            }
        }

        // A complete JSON value may be the final line even when the writer omitted a trailing newline.
        if !discardingOversizedLine, !pending.isEmpty {
            process(line: pending[pending.startIndex..<pending.endIndex], state: &state)
        }

        fileScanCache[path] = FileScanCache(
            fileSize: fileSize,
            modificationDate: modificationDate,
            endedWithNewline: endedWithNewline,
            state: state
        )
        return state.result
    }

    private func process(line: Data.SubSequence, state: inout ScanState) {
        autoreleasepool {
            guard line.count <= Self.maximumRelevantLineSize,
                  containsRelevantEvent(in: line),
                  let rawObject = try? JSONSerialization.jsonObject(with: Data(line)),
                  let object = rawObject as? [String: Any] else {
                return
            }

            let entryType = (object["type"] as? String) ?? ""
            if entryType == "turn_context" {
                state.currentModel = extractModel(fromTurnContext: object) ?? state.currentModel
                return
            }

            if entryType == "session_meta" {
                state.workspacePath = extractWorkspacePath(fromSessionMeta: object) ?? state.workspacePath
                return
            }

            if entryType == "event_msg" || entryType.isEmpty {
                let payload = object["payload"] as? [String: Any]
                let payloadType = payload?["type"] as? String

                if payloadType == "agent_message" {
                    guard let timestampMS = readTimestampMS(from: object) else {
                        return
                    }
                    registerAgentRun(timestampMS, daily: &state.daily, seenRuns: &state.seenRuns)
                    trackActivity(timestampMS, daily: &state.daily, lastActivityMS: &state.lastActivityMS)
                    return
                }

                if payloadType == "agent_reasoning" {
                    guard let timestampMS = readTimestampMS(from: object) else {
                        return
                    }
                    trackActivity(timestampMS, daily: &state.daily, lastActivityMS: &state.lastActivityMS)
                    return
                }

                guard payloadType == "token_count",
                      let info = payload?["info"] as? [String: Any] else {
                    return
                }

                let usage = extractUsage(from: info)
                guard let usage else {
                    return
                }

                var delta = UsageTotals(
                    input: usage.input,
                    cached: usage.cached,
                    output: usage.output
                )

                if usage.usedTotal {
                    delta = UsageTotals(
                        input: max(0, usage.input - state.previousTotals.input),
                        cached: max(0, usage.cached - state.previousTotals.cached),
                        output: max(0, usage.output - state.previousTotals.output)
                    )
                    state.previousTotals = UsageTotals(
                        input: usage.input,
                        cached: usage.cached,
                        output: usage.output
                    )
                } else {
                    state.previousTotals.input += delta.input
                    state.previousTotals.cached += delta.cached
                    state.previousTotals.output += delta.output
                }

                guard delta.input > 0 || delta.cached > 0 || delta.output > 0 else {
                    return
                }

                guard let timestampMS = readTimestampMS(from: object),
                      let dayKey = dayKey(forTimestampMS: timestampMS),
                      var entry = state.daily[dayKey] else {
                    return
                }

                let cached = min(delta.cached, delta.input)
                entry.input += delta.input
                entry.cached += cached
                entry.output += delta.output
                state.daily[dayKey] = entry

                let modelName = state.currentModel
                    ?? extractModel(fromTokenCount: object)
                    ?? "unknown"
                state.modelTotals[modelName, default: 0] += delta.input + delta.output

                trackActivity(timestampMS, daily: &state.daily, lastActivityMS: &state.lastActivityMS)
                return
            }

            guard entryType == "response_item",
                  let payload = object["payload"] as? [String: Any] else {
                return
            }

            let role = payload["role"] as? String
            let payloadType = payload["type"] as? String
            guard let timestampMS = readTimestampMS(from: object) else {
                return
            }

            if role == "assistant" {
                registerAgentRun(timestampMS, daily: &state.daily, seenRuns: &state.seenRuns)
                trackActivity(timestampMS, daily: &state.daily, lastActivityMS: &state.lastActivityMS)
                return
            }

            if payloadType != "message" {
                trackActivity(timestampMS, daily: &state.daily, lastActivityMS: &state.lastActivityMS)
            }
        }
    }

    private func containsRelevantEvent(in line: Data.SubSequence) -> Bool {
        line.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            let prefix = Self.jsonTypePrefix
            // Both the envelope type and nested payload type occur near the start of Codex JSONL entries.
            let searchLimit = min(bytes.count, 1_024)
            guard prefix.count < searchLimit else {
                return false
            }

            for start in 0...(searchLimit - prefix.count) where bytes[start] == prefix[0] {
                guard prefix.indices.allSatisfy({ bytes[start + $0] == prefix[$0] }) else {
                    continue
                }
                let valueStart = start + prefix.count
                for eventType in Self.relevantEventTypes {
                    guard valueStart + eventType.count <= searchLimit else {
                        continue
                    }
                    if eventType.indices.allSatisfy({ bytes[valueStart + $0] == eventType[$0] }) {
                        return true
                    }
                }
            }
            return false
        }
    }

    private func buildSnapshot(
        updatedAt: Date,
        dayKeys: [String],
        daily: [String: DailyTotals],
        modelTotals: [String: Int],
        workspaces: [LocalUsageWorkspace] = []
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
            topModels: Array(topModels),
            workspaces: workspaces
        )
    }

    private func merge(_ source: [String: DailyTotals], into target: inout [String: DailyTotals]) {
        for (dayKey, sourceTotals) in source {
            guard var targetTotals = target[dayKey] else {
                continue
            }
            targetTotals.input += sourceTotals.input
            targetTotals.cached += sourceTotals.cached
            targetTotals.output += sourceTotals.output
            targetTotals.agentTimeMS += sourceTotals.agentTimeMS
            targetTotals.agentRuns += sourceTotals.agentRuns
            target[dayKey] = targetTotals
        }
    }

    private func merge(_ source: [String: Int], into target: inout [String: Int]) {
        for (key, value) in source {
            target[key, default: 0] += value
        }
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

    private func extractWorkspacePath(fromSessionMeta object: [String: Any]) -> String? {
        guard let payload = object["payload"] as? [String: Any],
              let rawPath = payload["cwd"] as? String else {
            return nil
        }
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path).standardizedFileURL.path
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
