import CodexIslandCore
import SwiftUI

struct UsageDashboardView: View {
    @Binding var metric: UsageDashboardMetric
    let snapshot: LocalUsageSnapshot?
    private let presentation: UsageDashboardPresentation
    @State private var hoveredChartBarID: String?

    private let gridColumns = [
        GridItem(.flexible(minimum: 170), spacing: 12),
        GridItem(.flexible(minimum: 170), spacing: 12),
        GridItem(.flexible(minimum: 170), spacing: 12),
        GridItem(.flexible(minimum: 170), spacing: 12),
    ]
    private let secondaryGridColumns = [
        GridItem(.flexible(minimum: 200), spacing: 12),
        GridItem(.flexible(minimum: 200), spacing: 12),
        GridItem(.flexible(minimum: 200), spacing: 12),
    ]
    private let modelColumns = [
        GridItem(.adaptive(minimum: 140), spacing: 8)
    ]

    init(metric: Binding<UsageDashboardMetric>, snapshot: LocalUsageSnapshot?) {
        _metric = metric
        self.snapshot = snapshot
        presentation = UsageDashboardPresentation(snapshot: snapshot, metric: metric.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 12) {
                ForEach(Array(presentation.cards.prefix(4))) { card in
                    statCard(card)
                }
            }

            LazyVGrid(columns: secondaryGridColumns, alignment: .leading, spacing: 12) {
                ForEach(Array(presentation.cards.dropFirst(4))) { card in
                    statCard(card)
                }
            }

            chartCard

            HStack(alignment: .top, spacing: 12) {
                LazyVGrid(columns: [
                    GridItem(.flexible(minimum: 190), spacing: 12),
                    GridItem(.flexible(minimum: 190), spacing: 12),
                ], spacing: 12) {
                    ForEach(presentation.insights) { card in
                        statCard(card)
                    }
                }
                .frame(maxWidth: .infinity)

                topModelsSection
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("USAGE")
                .font(.system(size: 15, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(UsageDashboardPalette.title)

            workspacePill

            Spacer(minLength: 16)

            Text(updatedLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(UsageDashboardPalette.muted)

            HStack(spacing: 4) {
                ForEach(UsageDashboardMetric.allCases) { currentMetric in
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            metric = currentMetric
                        }
                    } label: {
                        Text(currentMetric.title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(
                                metric == currentMetric
                                    ? UsageDashboardPalette.title
                                    : UsageDashboardPalette.subtitle
                            )
                            .frame(minWidth: 58)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 5)
                            .background(
                                metric == currentMetric
                                    ? Color.white.opacity(0.12)
                                    : Color.clear,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.white.opacity(0.045), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
            )
        }
    }

    private var workspacePill: some View {
        HStack(spacing: 10) {
            Text("All workspaces")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(UsageDashboardPalette.title)

            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(UsageDashboardPalette.muted)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.065), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func statCard(_ card: UsageStatCard) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(card.label.uppercased())
                .font(.system(size: 9, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(UsageDashboardPalette.muted)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(card.value)
                    .font(.system(size: card.compact ? 21 : 25, weight: .semibold))
                    .foregroundStyle(UsageDashboardPalette.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if let suffix = card.suffix {
                    Text(suffix.uppercased())
                        .font(.system(size: 9, weight: .medium))
                        .tracking(1.1)
                        .foregroundStyle(UsageDashboardPalette.muted)
                        .lineLimit(1)
                }
            }

            Text(card.caption)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(UsageDashboardPalette.subtitle)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: card.compact ? 52 : 62, alignment: .topLeading)
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(presentation.chartTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(UsageDashboardPalette.title)
            }

            chart
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var chart: some View {
        GeometryReader { proxy in
            let values = presentation.chartBars.map(\.value)
            let maxValue = max(values.max() ?? 0, 1)
            let chartHeight = max(48, proxy.size.height - 26)

            HStack(alignment: .bottom, spacing: 10) {
                ForEach(presentation.chartBars) { bar in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        UsageDashboardPalette.accent,
                                        UsageDashboardPalette.accent.opacity(0.48),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: barHeight(value: bar.value, maxValue: maxValue, chartHeight: chartHeight))
                            .overlay(alignment: .top) {
                                if hoveredChartBarID == bar.id {
                                    chartTooltip(for: bar)
                                        .fixedSize()
                                        .offset(y: -42)
                                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
                                }
                            }

                        Text(bar.label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(UsageDashboardPalette.subtitle)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                    .contentShape(Rectangle())
                    .onHover { isHovering in
                        withAnimation(.easeOut(duration: 0.1)) {
                            if isHovering {
                                hoveredChartBarID = bar.id
                            } else if hoveredChartBarID == bar.id {
                                hoveredChartBarID = nil
                            }
                        }
                    }
                    .zIndex(hoveredChartBarID == bar.id ? 1 : 0)
                }
            }
        }
        .frame(height: 120)
    }

    private func chartTooltip(for bar: UsageChartBar) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(bar.label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(UsageDashboardPalette.muted)

            Text(exactChartValue(bar.value))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(UsageDashboardPalette.title)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.94), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 8, y: 4)
        .allowsHitTesting(false)
    }

    private func exactChartValue(_ value: Int) -> String {
        switch metric {
        case .tokens:
            return "\(formatCount(value)) tokens"
        case .time:
            return formatDuration(value)
        }
    }

    private var topModelsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TOP MODELS")
                .font(.system(size: 9, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(UsageDashboardPalette.muted)

            if presentation.topModels.isEmpty {
                Text("No model usage found yet")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(UsageDashboardPalette.subtitle)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(cardBackground, in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )
            } else {
                LazyVGrid(columns: modelColumns, alignment: .leading, spacing: 8) {
                    ForEach(presentation.topModels) { model in
                        HStack(spacing: 8) {
                            Text(model.model)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(UsageDashboardPalette.title)

                            Text("\(formatPercent(model.sharePercent))%")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(UsageDashboardPalette.subtitle)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(cardBackground, in: Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var cardBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.08),
                Color.white.opacity(0.035),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var updatedLabel: String {
        guard let snapshot else {
            return "Loading local usage"
        }
        return "Updated \(relativeTime(from: snapshot.updatedAt)) ago"
    }

    private func barHeight(value: Int, maxValue: Int, chartHeight: CGFloat) -> CGFloat {
        guard value > 0 else {
            return 12
        }
        let normalized = CGFloat(Double(value) / Double(maxValue))
        return max(12, normalized * chartHeight)
    }

    private func relativeTime(from date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 {
            return "\(seconds)s"
        }
        if seconds < 3_600 {
            return "\(seconds / 60)m"
        }
        if seconds < 86_400 {
            return "\(seconds / 3_600)h"
        }
        return "\(seconds / 86_400)d"
    }
}

private enum UsageDashboardPalette {
    static let title = Color.white.opacity(0.95)
    static let muted = Color.white.opacity(0.46)
    static let subtitle = Color.white.opacity(0.68)
    static let accent = Color(red: 0.28, green: 0.86, blue: 0.55)
}

private struct UsageStatCard: Identifiable {
    let id: String
    let label: String
    let value: String
    let suffix: String?
    let caption: String
    let compact: Bool
}

private struct UsageChartBar: Identifiable {
    let id: String
    let label: String
    let value: Int
}

private struct UsageDashboardPresentation {
    let cards: [UsageStatCard]
    let insights: [UsageStatCard]
    let chartBars: [UsageChartBar]
    let chartTitle: String
    let topModels: [LocalUsageModel]

    init(snapshot: LocalUsageSnapshot?, metric: UsageDashboardMetric) {
        let emptySnapshot = snapshot ?? LocalUsageSnapshot.empty()
        let usageDays = emptySnapshot.days
        let latestDay = usageDays.last
        let last7Days = Array(usageDays.suffix(7))
        let last7Tokens = last7Days.reduce(0) { $0 + $1.totalTokens }
        let last7Input = last7Days.reduce(0) { $0 + $1.inputTokens }
        let last7Cached = last7Days.reduce(0) { $0 + $1.cachedInputTokens }
        let last7AgentTimeMS = last7Days.reduce(0) { $0 + $1.agentTimeMS }
        let last30AgentTimeMS = usageDays.reduce(0) { $0 + $1.agentTimeMS }
        let last7AgentRuns = last7Days.reduce(0) { $0 + $1.agentRuns }
        let last30AgentRuns = usageDays.reduce(0) { $0 + $1.agentRuns }
        let averageDailyAgentTimeMS = last7Days.isEmpty ? 0 : Int((Double(last7AgentTimeMS) / Double(last7Days.count)).rounded())
        let averageTokensPerRun = last7AgentRuns == 0 ? nil : Int((Double(last7Tokens) / Double(last7AgentRuns)).rounded())
        let averageDurationPerRunMS = last7AgentRuns == 0 ? nil : Int((Double(last7AgentTimeMS) / Double(last7AgentRuns)).rounded())
        let activeLast7Days = last7Days.filter(isActiveDay).count
        let activeAllDays = usageDays.filter(isActiveDay).count
        let averagePerActiveDayMS = activeLast7Days == 0 ? nil : Int((Double(last7AgentTimeMS) / Double(activeLast7Days)).rounded())
        let peakAgentDay = usageDays.max { $0.agentTimeMS < $1.agentTimeMS }
        let longestStreak = UsageDashboardPresentation.longestStreak(in: usageDays)

        if metric == .tokens {
            cards = [
                UsageStatCard(
                    id: "today",
                    label: "Today",
                    value: formatCompactNumber(latestDay?.totalTokens ?? 0),
                    suffix: "tokens",
                    caption: latestDay.map {
                        "\(formatDayLabel($0.dayKey)) · \(formatCount($0.inputTokens)) in / \(formatCount($0.outputTokens)) out"
                    } ?? "Latest available day",
                    compact: false
                ),
                UsageStatCard(
                    id: "last7",
                    label: "Last 7 days",
                    value: formatCompactNumber(emptySnapshot.totals.last7DaysTokens),
                    suffix: "tokens",
                    caption: "Avg \(formatCompactNumber(emptySnapshot.totals.averageDailyTokens)) / day",
                    compact: false
                ),
                UsageStatCard(
                    id: "last30",
                    label: "Last 30 days",
                    value: formatCompactNumber(emptySnapshot.totals.last30DaysTokens),
                    suffix: "tokens",
                    caption: "Total \(formatCount(emptySnapshot.totals.last30DaysTokens))",
                    compact: false
                ),
                UsageStatCard(
                    id: "cacheHitRate",
                    label: "Cache hit rate",
                    value: formatPercent(emptySnapshot.totals.cacheHitRatePercent) + "%",
                    suffix: nil,
                    caption: "Last 7 days",
                    compact: false
                ),
                UsageStatCard(
                    id: "cachedTokens",
                    label: "Cached tokens",
                    value: formatCompactNumber(last7Cached),
                    suffix: "saved",
                    caption: last7Input == 0 ? "Last 7 days" : "\(formatPercent((Double(last7Cached) / Double(last7Input)) * 100))% of prompt tokens",
                    compact: false
                ),
                UsageStatCard(
                    id: "avgPerRun",
                    label: "Avg / run",
                    value: averageTokensPerRun.map(formatCompactNumber) ?? "--",
                    suffix: "tokens",
                    caption: last7AgentRuns == 0 ? "No runs yet" : "\(formatCount(last7AgentRuns)) runs in last 7 days",
                    compact: false
                ),
                UsageStatCard(
                    id: "peakDay",
                    label: "Peak day",
                    value: formatDayLabel(emptySnapshot.totals.peakDay),
                    suffix: nil,
                    caption: "\(formatCompactNumber(emptySnapshot.totals.peakDayTokens)) tokens",
                    compact: false
                ),
            ]
            chartBars = last7Days.map {
                UsageChartBar(id: $0.id, label: formatShortDayLabel($0.dayKey), value: $0.totalTokens)
            }
            chartTitle = formatDayRange(last7Days)
        } else {
            cards = [
                UsageStatCard(
                    id: "last7Time",
                    label: "Last 7 days",
                    value: formatCompactDuration(last7AgentTimeMS),
                    suffix: "agent time",
                    caption: "Avg \(formatCompactDuration(averageDailyAgentTimeMS)) / day",
                    compact: false
                ),
                UsageStatCard(
                    id: "last30Time",
                    label: "Last 30 days",
                    value: formatCompactDuration(last30AgentTimeMS),
                    suffix: "agent time",
                    caption: "Total \(formatDuration(last30AgentTimeMS))",
                    compact: false
                ),
                UsageStatCard(
                    id: "runs",
                    label: "Runs",
                    value: formatCount(last7AgentRuns),
                    suffix: "runs",
                    caption: "Last 30 days: \(formatCount(last30AgentRuns)) runs",
                    compact: false
                ),
                UsageStatCard(
                    id: "avgRunTime",
                    label: "Avg / run",
                    value: averageDurationPerRunMS.map(formatCompactDuration) ?? "--",
                    suffix: nil,
                    caption: last7AgentRuns == 0 ? "No runs yet" : "Across \(formatCount(last7AgentRuns)) runs",
                    compact: false
                ),
                UsageStatCard(
                    id: "avgActiveDay",
                    label: "Avg / active day",
                    value: averagePerActiveDayMS.map(formatCompactDuration) ?? "--",
                    suffix: nil,
                    caption: activeLast7Days == 0 ? "No active days yet" : "\(formatCount(activeLast7Days)) active days in last 7",
                    compact: false
                ),
                UsageStatCard(
                    id: "peakAgentDay",
                    label: "Peak day",
                    value: formatDayLabel(peakAgentDay?.dayKey),
                    suffix: nil,
                    caption: "\(formatCompactDuration(peakAgentDay?.agentTimeMS ?? 0)) agent time",
                    compact: false
                ),
            ]
            chartBars = last7Days.map {
                UsageChartBar(id: $0.id, label: formatShortDayLabel($0.dayKey), value: $0.agentTimeMS)
            }
            chartTitle = formatDayRange(last7Days)
        }

        insights = [
            UsageStatCard(
                id: "longestStreak",
                label: "Longest streak",
                value: longestStreak == 0 ? "--" : "\(longestStreak) days",
                suffix: nil,
                caption: longestStreak == 0 ? "No active streak yet" : "Across current usage range",
                compact: true
            ),
            UsageStatCard(
                id: "activeDays",
                label: "Active days",
                value: last7Days.isEmpty ? "--" : "\(activeLast7Days) / \(last7Days.count)",
                suffix: nil,
                caption: usageDays.isEmpty ? "No activity yet" : "\(activeAllDays) / \(usageDays.count) in current range",
                compact: true
            ),
        ]

        topModels = emptySnapshot.topModels
    }

    private static func longestStreak(in usageDays: [LocalUsageDay]) -> Int {
        var longest = 0
        var current = 0

        for day in usageDays {
            if isActiveDay(day) {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }

        return longest
    }
}

private func formatCompactNumber(_ value: Int) -> String {
    let absolute = Double(abs(value))
    let sign = value < 0 ? "-" : ""

    switch absolute {
    case 1_000_000_000...:
        return sign + trimTrailingZero(absolute / 1_000_000_000) + "b"
    case 1_000_000...:
        return sign + trimTrailingZero(absolute / 1_000_000) + "m"
    case 1_000...:
        return sign + trimTrailingZero(absolute / 1_000) + "k"
    default:
        return "\(value)"
    }
}

private func trimTrailingZero(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    if rounded.rounded() == rounded {
        return String(Int(rounded))
    }
    return String(format: "%.1f", rounded)
}

private func formatCount(_ value: Int) -> String {
    usageCountFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
}

private func formatPercent(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    if rounded.rounded() == rounded {
        return String(Int(rounded))
    }
    return String(format: "%.1f", rounded)
}

private func formatDayRange(_ days: [LocalUsageDay]) -> String {
    guard let firstDay = days.first, let lastDay = days.last else {
        return "Last 7 days"
    }
    return "\(formatDayLabel(firstDay.dayKey)) - \(formatDayLabel(lastDay.dayKey))"
}

private func formatDayLabel(_ dayKey: String?) -> String {
    guard let dayKey,
          let date = usageDayKeyFormatter.date(from: dayKey) else {
        return "--"
    }
    return usageDisplayDayFormatter.string(from: date)
}

private func formatShortDayLabel(_ dayKey: String) -> String {
    guard let date = usageDayKeyFormatter.date(from: dayKey) else {
        return dayKey
    }
    return usageDisplayDayFormatter.string(from: date)
}

private func formatCompactDuration(_ milliseconds: Int) -> String {
    guard milliseconds > 0 else {
        return "0m"
    }

    let totalMinutes = Int((Double(milliseconds) / 60_000).rounded())
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60

    if hours > 0 {
        return "\(hours)h \(minutes)m"
    }
    return "\(minutes)m"
}

private func formatDuration(_ milliseconds: Int) -> String {
    guard milliseconds > 0 else {
        return "0 minutes"
    }

    let totalMinutes = Int((Double(milliseconds) / 60_000).rounded())
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60

    if hours > 0 && minutes > 0 {
        return "\(hours)h \(minutes)m"
    }
    if hours > 0 {
        return "\(hours)h"
    }
    return "\(minutes)m"
}

private func isActiveDay(_ day: LocalUsageDay) -> Bool {
    day.totalTokens > 0 || day.agentTimeMS > 0 || day.agentRuns > 0
}

private let usageDayKeyFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = .autoupdatingCurrent
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

private let usageDisplayDayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = .autoupdatingCurrent
    formatter.locale = .autoupdatingCurrent
    formatter.setLocalizedDateFormatFromTemplate("M d")
    return formatter
}()

private let usageCountFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter
}()
