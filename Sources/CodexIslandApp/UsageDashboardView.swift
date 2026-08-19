import CodexIslandCore
import SwiftUI

struct UsageDashboardView: View {
    @Binding var metric: UsageDashboardMetric
    let snapshot: LocalUsageSnapshot?
    let language: InterfaceLanguage
    @AppStorage("workspaceSortMode") private var workspaceSortModeRaw = WorkspaceSortMode.usage.rawValue
    @State private var hoveredChartBarID: String?
    @State private var hoveredStatCardID: String?
    @State private var isWorkspacePickerHovered = false
    @State private var isWorkspacePickerOpen = false
    @State private var selectedWorkspaceID: String?

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
    init(metric: Binding<UsageDashboardMetric>, snapshot: LocalUsageSnapshot?, language: InterfaceLanguage) {
        _metric = metric
        self.snapshot = snapshot
        self.language = language
    }

    private var filteredSnapshot: LocalUsageSnapshot? {
        snapshot?.filtered(toWorkspaceID: selectedWorkspaceID)
    }

    private var presentation: UsageDashboardPresentation {
        UsageDashboardPresentation(snapshot: filteredSnapshot, metric: metric, language: language)
    }

    private var sortedWorkspaces: [LocalUsageWorkspace] {
        (snapshot?.workspaces ?? []).sorted(by: workspaceSortsBefore)
    }

    private var workspaceSortMode: WorkspaceSortMode {
        WorkspaceSortMode(rawValue: workspaceSortModeRaw) ?? .usage
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
        .onChange(of: snapshot?.workspaces.map(\.id) ?? []) { _, workspaceIDs in
            if let selectedWorkspaceID, !workspaceIDs.contains(selectedWorkspaceID) {
                self.selectedWorkspaceID = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(language.text("USAGE", "用量"))
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
                        Text(currentMetric.title(language: language))
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
        .zIndex(50)
    }

    private var workspacePill: some View {
        Button {
            withAnimation(.easeOut(duration: 0.14)) {
                isWorkspacePickerOpen.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(UsageDashboardPalette.accent)

                Text(selectedWorkspaceName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(UsageDashboardPalette.title)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Divider()
                    .overlay(Color.white.opacity(0.14))
                    .frame(height: 14)

                ZStack {
                    Circle()
                        .fill(
                            isWorkspacePickerHovered
                                ? UsageDashboardPalette.accent.opacity(0.24)
                                : UsageDashboardPalette.accent.opacity(0.15)
                        )

                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(UsageDashboardPalette.title)
                        .rotationEffect(.degrees(isWorkspacePickerOpen ? 180 : 0))
                }
                .frame(width: 20, height: 20)
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(
                isWorkspacePickerHovered
                    ? UsageDashboardPalette.accent.opacity(0.16)
                    : UsageDashboardPalette.accent.opacity(0.09),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isWorkspacePickerHovered
                            ? UsageDashboardPalette.accent.opacity(0.7)
                            : UsageDashboardPalette.accent.opacity(0.34),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: isWorkspacePickerHovered
                    ? UsageDashboardPalette.accent.opacity(0.16)
                    : Color.black.opacity(0.18),
                radius: isWorkspacePickerHovered ? 8 : 3,
                y: 2
            )
            .scaleEffect(isWorkspacePickerHovered ? 1.025 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
        .overlay(alignment: .topLeading) {
            if isWorkspacePickerOpen {
                workspaceDropdown
                    .offset(y: 36)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topLeading)))
            }
        }
        .zIndex(100)
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isWorkspacePickerHovered = isHovering
            }
        }
        .help(language.text("Filter usage by workspace", "按工作区筛选用量"))
    }

    private var workspaceDropdown: some View {
        let workspaces = sortedWorkspaces
        let rowCount = workspaces.count + 1
        let listHeight = min(CGFloat(rowCount * 32 + 12), 204)

        return VStack(spacing: 0) {
            workspaceSortPicker

            Divider()
                .overlay(Color.white.opacity(0.08))

            ScrollView {
                LazyVStack(spacing: 2) {
                    workspaceOptionButton(
                        title: language.text("All workspaces", "全部工作区"),
                        path: nil,
                        workspaceID: nil
                    )

                    if !workspaces.isEmpty {
                        Divider()
                            .overlay(Color.white.opacity(0.08))
                            .padding(.vertical, 3)

                        ForEach(workspaces) { workspace in
                            workspaceOptionButton(
                                title: workspace.name,
                                path: workspace.path,
                                workspaceID: workspace.id
                            )
                        }
                    }
                }
                .padding(6)
            }
            .scrollIndicators(.visible)
            .frame(height: listHeight)
        }
        .frame(width: 270)
        .background(Color(red: 0.055, green: 0.06, blue: 0.07).opacity(0.99))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.5), radius: 18, y: 10)
    }

    private var workspaceSortPicker: some View {
        HStack(spacing: 4) {
            Text(language.text("Sort", "排序"))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(UsageDashboardPalette.muted)

            Spacer(minLength: 4)

            ForEach(WorkspaceSortMode.allCases) { mode in
                Button {
                    withAnimation(.easeOut(duration: 0.14)) {
                        workspaceSortModeRaw = mode.rawValue
                    }
                } label: {
                    Text(mode.title(language: language))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(
                            workspaceSortMode == mode
                                ? UsageDashboardPalette.title
                                : UsageDashboardPalette.subtitle
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            workspaceSortMode == mode
                                ? UsageDashboardPalette.accent.opacity(0.2)
                                : Color.clear,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    workspaceSortMode == mode
                                        ? UsageDashboardPalette.accent.opacity(0.42)
                                        : Color.clear,
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
    }

    private func workspaceSortsBefore(_ lhs: LocalUsageWorkspace, _ rhs: LocalUsageWorkspace) -> Bool {
        let lhsUsage = workspaceUsageValue(lhs)
        let rhsUsage = workspaceUsageValue(rhs)
        let lhsRecentActivity = mostRecentActivityIndex(lhs)
        let rhsRecentActivity = mostRecentActivityIndex(rhs)

        switch workspaceSortMode {
        case .usage:
            if lhsUsage != rhsUsage {
                return lhsUsage > rhsUsage
            }
            if lhsRecentActivity != rhsRecentActivity {
                return lhsRecentActivity > rhsRecentActivity
            }
        case .recent:
            if lhsRecentActivity != rhsRecentActivity {
                return lhsRecentActivity > rhsRecentActivity
            }
            if lhsUsage != rhsUsage {
                return lhsUsage > rhsUsage
            }
        case .name:
            let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }
        }

        return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
    }

    private func workspaceUsageValue(_ workspace: LocalUsageWorkspace) -> Int {
        switch metric {
        case .tokens:
            return workspace.totals.last30DaysTokens
        case .time:
            return workspace.days.reduce(0) { $0 + $1.agentTimeMS }
        }
    }

    private func mostRecentActivityIndex(_ workspace: LocalUsageWorkspace) -> Int {
        workspace.days.lastIndex {
            $0.totalTokens > 0 || $0.agentTimeMS > 0 || $0.agentRuns > 0
        } ?? -1
    }

    private func workspaceOptionButton(title: String, path: String?, workspaceID: String?) -> some View {
        let isSelected = selectedWorkspaceID == workspaceID

        return Button {
            selectedWorkspaceID = workspaceID
            withAnimation(.easeOut(duration: 0.12)) {
                isWorkspacePickerOpen = false
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "folder")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? UsageDashboardPalette.accent : UsageDashboardPalette.muted)
                    .frame(width: 15)

                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? UsageDashboardPalette.title : UsageDashboardPalette.subtitle)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(
                isSelected ? UsageDashboardPalette.accent.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(path ?? language.text("Show usage for all workspaces", "显示全部工作区用量"))
    }

    private var selectedWorkspaceName: String {
        guard let selectedWorkspaceID,
              let workspace = snapshot?.workspaces.first(where: { $0.id == selectedWorkspaceID }) else {
            return language.text("All workspaces", "全部工作区")
        }
        return workspace.name
    }

    private func statCard(_ card: UsageStatCard) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(card.label.uppercased())
                .font(.system(size: 9, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(UsageDashboardPalette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    statValue(card)

                    if let suffix = card.suffix {
                        statSuffix(suffix)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)

                statValue(card)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(card.caption)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(UsageDashboardPalette.subtitle)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: card.compact ? 52 : 62, alignment: .topLeading)
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    hoveredStatCardID == card.id
                        ? UsageDashboardPalette.accent.opacity(0.34)
                        : Color.white.opacity(0.06),
                    lineWidth: 1
                )
        )
        .shadow(
            color: hoveredStatCardID == card.id ? Color.black.opacity(0.34) : .clear,
            radius: 16,
            y: 8
        )
        .scaleEffect(hoveredStatCardID == card.id ? 1.08 : 1)
        .zIndex(hoveredStatCardID == card.id ? 10 : 0)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { isHovering in
            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                hoveredStatCardID = isHovering ? card.id : nil
            }
        }
    }

    private func statValue(_ card: UsageStatCard) -> some View {
        Text(card.value)
            .font(.system(size: card.compact ? 21 : 25, weight: .semibold))
            .foregroundStyle(UsageDashboardPalette.title)
            .lineLimit(1)
            .allowsTightening(true)
            .minimumScaleFactor(0.62)
    }

    private func statSuffix(_ suffix: String) -> some View {
        Text(suffix.uppercased())
            .font(.system(size: 9, weight: .medium))
            .tracking(1.1)
            .foregroundStyle(UsageDashboardPalette.muted)
            .lineLimit(1)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
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
            return language.text("\(formatCount(value)) tokens", "\(formatCount(value)) Token")
        case .time:
            return formatDuration(value, language: language)
        }
    }

    private var topModelsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(language.text("TOP MODELS", "常用模型"))
                .font(.system(size: 9, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(UsageDashboardPalette.muted)

            if presentation.topModels.isEmpty {
                Text(language.text("No model usage found yet", "尚未发现模型用量"))
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
                HStack(spacing: 18) {
                    modelShareRing

                    VStack(spacing: 9) {
                        ForEach(Array(presentation.topModels.prefix(2).enumerated()), id: \.element.id) { index, model in
                            modelLegendRow(model, color: modelColor(at: index))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var modelShareRing: some View {
        let models = Array(presentation.topModels.prefix(2))

        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 6)

            ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                Circle()
                    .trim(
                        from: modelShareStart(at: index, models: models),
                        to: modelShareEnd(at: index, models: models)
                    )
                    .stroke(
                        modelColor(at: index),
                        style: StrokeStyle(lineWidth: 6, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90))
            }

            Text("\(formatPercent(models.first?.sharePercent ?? 0))%")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(UsageDashboardPalette.title)
                .minimumScaleFactor(0.72)
                .lineLimit(1)
        }
        .frame(width: 46, height: 46)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(language.text("Top model share", "首位模型占比"))
        .accessibilityValue("\(formatPercent(models.first?.sharePercent ?? 0))%")
    }

    private func modelLegendRow(_ model: LocalUsageModel, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)

            Text(model.model)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(UsageDashboardPalette.title)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 6)

            Text("\(formatPercent(model.sharePercent))%")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(UsageDashboardPalette.subtitle)
                .monospacedDigit()
        }
    }

    private func modelColor(at index: Int) -> Color {
        index == 0 ? UsageDashboardPalette.accent : Color.white.opacity(0.52)
    }

    private func modelShareStart(at index: Int, models: [LocalUsageModel]) -> Double {
        models.prefix(index).reduce(0) { $0 + clampedModelShare($1.sharePercent) }
    }

    private func modelShareEnd(at index: Int, models: [LocalUsageModel]) -> Double {
        min(
            modelShareStart(at: index, models: models) + clampedModelShare(models[index].sharePercent),
            1
        )
    }

    private func clampedModelShare(_ percent: Double) -> Double {
        min(max(percent / 100, 0), 1)
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
            return language.text("Loading local usage", "正在加载本地用量")
        }
        return language.text(
            "Updated \(relativeTime(from: snapshot.updatedAt)) ago",
            "更新于 \(relativeTime(from: snapshot.updatedAt))前"
        )
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
            return language.text("\(seconds)s", "\(seconds)秒")
        }
        if seconds < 3_600 {
            return language.text("\(seconds / 60)m", "\(seconds / 60)分钟")
        }
        if seconds < 86_400 {
            return language.text("\(seconds / 3_600)h", "\(seconds / 3_600)小时")
        }
        return language.text("\(seconds / 86_400)d", "\(seconds / 86_400)天")
    }
}

private enum WorkspaceSortMode: String, CaseIterable, Identifiable {
    case usage
    case recent
    case name

    var id: String { rawValue }

    func title(language: InterfaceLanguage) -> String {
        switch self {
        case .usage:
            return language.text("Usage", "用量")
        case .recent:
            return language.text("Recent", "最近")
        case .name:
            return language.text("Name", "名称")
        }
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

    init(snapshot: LocalUsageSnapshot?, metric: UsageDashboardMetric, language: InterfaceLanguage) {
        let emptySnapshot = snapshot ?? LocalUsageSnapshot.empty()
        let text: (String, String) -> String = { language.text($0, $1) }
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
                    label: text("Today", "今天"),
                    value: formatCompactNumber(latestDay?.totalTokens ?? 0),
                    suffix: text("tokens", "Token"),
                    caption: latestDay.map {
                        text(
                            "\(formatDayLabel($0.dayKey, language: language)) · \(formatCount($0.inputTokens)) in / \(formatCount($0.outputTokens)) out",
                            "\(formatDayLabel($0.dayKey, language: language)) · 输入 \(formatCount($0.inputTokens)) / 输出 \(formatCount($0.outputTokens))"
                        )
                    } ?? text("Latest available day", "最近有数据的一天"),
                    compact: false
                ),
                UsageStatCard(
                    id: "last7",
                    label: text("Last 7 days", "最近 7 天"),
                    value: formatCompactNumber(emptySnapshot.totals.last7DaysTokens),
                    suffix: text("tokens", "Token"),
                    caption: text(
                        "Avg \(formatCompactNumber(emptySnapshot.totals.averageDailyTokens)) / day",
                        "日均 \(formatCompactNumber(emptySnapshot.totals.averageDailyTokens))"
                    ),
                    compact: false
                ),
                UsageStatCard(
                    id: "last30",
                    label: text("Last 30 days", "最近 30 天"),
                    value: formatCompactNumber(emptySnapshot.totals.last30DaysTokens),
                    suffix: text("tokens", "Token"),
                    caption: text(
                        "Total \(formatCount(emptySnapshot.totals.last30DaysTokens))",
                        "共 \(formatCount(emptySnapshot.totals.last30DaysTokens))"
                    ),
                    compact: false
                ),
                UsageStatCard(
                    id: "cacheHitRate",
                    label: text("Cache hit rate", "缓存命中率"),
                    value: formatPercent(emptySnapshot.totals.cacheHitRatePercent) + "%",
                    suffix: nil,
                    caption: text("Last 7 days", "最近 7 天"),
                    compact: false
                ),
                UsageStatCard(
                    id: "cachedTokens",
                    label: text("Cached tokens", "缓存 Token"),
                    value: formatCompactNumber(last7Cached),
                    suffix: text("saved", "已节省"),
                    caption: last7Input == 0
                        ? text("Last 7 days", "最近 7 天")
                        : text(
                            "\(formatPercent((Double(last7Cached) / Double(last7Input)) * 100))% of prompt tokens",
                            "占提示词 Token 的 \(formatPercent((Double(last7Cached) / Double(last7Input)) * 100))%"
                        ),
                    compact: false
                ),
                UsageStatCard(
                    id: "avgPerRun",
                    label: text("Avg / run", "单次平均"),
                    value: averageTokensPerRun.map(formatCompactNumber) ?? "--",
                    suffix: text("tokens", "Token"),
                    caption: last7AgentRuns == 0
                        ? text("No runs yet", "暂无运行记录")
                        : text(
                            "\(formatCount(last7AgentRuns)) runs in last 7 days",
                            "最近 7 天运行 \(formatCount(last7AgentRuns)) 次"
                        ),
                    compact: false
                ),
                UsageStatCard(
                    id: "peakDay",
                    label: text("Peak day", "峰值日期"),
                    value: formatDayLabel(emptySnapshot.totals.peakDay, language: language),
                    suffix: nil,
                    caption: text(
                        "\(formatCompactNumber(emptySnapshot.totals.peakDayTokens)) tokens",
                        "\(formatCompactNumber(emptySnapshot.totals.peakDayTokens)) Token"
                    ),
                    compact: false
                ),
            ]
            chartBars = last7Days.map {
                UsageChartBar(id: $0.id, label: formatShortDayLabel($0.dayKey), value: $0.totalTokens)
            }
            chartTitle = formatDayRange(last7Days, language: language)
        } else {
            cards = [
                UsageStatCard(
                    id: "last7Time",
                    label: text("Last 7 days", "最近 7 天"),
                    value: formatCompactDuration(last7AgentTimeMS, language: language),
                    suffix: text("agent time", "执行时间"),
                    caption: text(
                        "Avg \(formatCompactDuration(averageDailyAgentTimeMS, language: language)) / day",
                        "日均 \(formatCompactDuration(averageDailyAgentTimeMS, language: language))"
                    ),
                    compact: false
                ),
                UsageStatCard(
                    id: "last30Time",
                    label: text("Last 30 days", "最近 30 天"),
                    value: formatCompactDuration(last30AgentTimeMS, language: language),
                    suffix: text("agent time", "执行时间"),
                    caption: text(
                        "Total \(formatDuration(last30AgentTimeMS, language: language))",
                        "总计 \(formatDuration(last30AgentTimeMS, language: language))"
                    ),
                    compact: false
                ),
                UsageStatCard(
                    id: "runs",
                    label: text("Runs", "运行次数"),
                    value: formatCount(last7AgentRuns),
                    suffix: text("runs", "次"),
                    caption: text(
                        "Last 30 days: \(formatCount(last30AgentRuns)) runs",
                        "最近 30 天：\(formatCount(last30AgentRuns)) 次"
                    ),
                    compact: false
                ),
                UsageStatCard(
                    id: "avgRunTime",
                    label: text("Avg / run", "单次平均"),
                    value: averageDurationPerRunMS.map { formatCompactDuration($0, language: language) } ?? "--",
                    suffix: nil,
                    caption: last7AgentRuns == 0
                        ? text("No runs yet", "暂无运行记录")
                        : text("Across \(formatCount(last7AgentRuns)) runs", "统计 \(formatCount(last7AgentRuns)) 次运行"),
                    compact: false
                ),
                UsageStatCard(
                    id: "avgActiveDay",
                    label: text("Avg / active day", "活跃日平均"),
                    value: averagePerActiveDayMS.map { formatCompactDuration($0, language: language) } ?? "--",
                    suffix: nil,
                    caption: activeLast7Days == 0
                        ? text("No active days yet", "暂无活跃日期")
                        : text(
                            "\(formatCount(activeLast7Days)) active days in last 7",
                            "最近 7 天活跃 \(formatCount(activeLast7Days)) 天"
                        ),
                    compact: false
                ),
                UsageStatCard(
                    id: "peakAgentDay",
                    label: text("Peak day", "峰值日期"),
                    value: formatDayLabel(peakAgentDay?.dayKey, language: language),
                    suffix: nil,
                    caption: text(
                        "\(formatCompactDuration(peakAgentDay?.agentTimeMS ?? 0, language: language)) agent time",
                        "执行时间 \(formatCompactDuration(peakAgentDay?.agentTimeMS ?? 0, language: language))"
                    ),
                    compact: false
                ),
            ]
            chartBars = last7Days.map {
                UsageChartBar(id: $0.id, label: formatShortDayLabel($0.dayKey), value: $0.agentTimeMS)
            }
            chartTitle = formatDayRange(last7Days, language: language)
        }

        insights = [
            UsageStatCard(
                id: "longestStreak",
                label: text("Longest streak", "最长连续使用"),
                value: longestStreak == 0 ? "--" : text("\(longestStreak) days", "\(longestStreak) 天"),
                suffix: nil,
                caption: longestStreak == 0
                    ? text("No active streak yet", "暂无连续使用记录")
                    : text("Across current usage range", "当前统计范围内"),
                compact: true
            ),
            UsageStatCard(
                id: "activeDays",
                label: text("Active days", "活跃天数"),
                value: last7Days.isEmpty ? "--" : "\(activeLast7Days) / \(last7Days.count)",
                suffix: nil,
                caption: usageDays.isEmpty
                    ? text("No activity yet", "暂无活动记录")
                    : text(
                        "\(activeAllDays) / \(usageDays.count) in current range",
                        "当前范围 \(activeAllDays) / \(usageDays.count) 天"
                    ),
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

private func formatDayRange(_ days: [LocalUsageDay], language: InterfaceLanguage) -> String {
    guard let firstDay = days.first, let lastDay = days.last else {
        return language.text("Last 7 days", "最近 7 天")
    }
    return "\(formatDayLabel(firstDay.dayKey, language: language)) - \(formatDayLabel(lastDay.dayKey, language: language))"
}

private func formatDayLabel(_ dayKey: String?, language: InterfaceLanguage) -> String {
    guard let dayKey,
          let date = usageDayKeyFormatter.date(from: dayKey) else {
        return "--"
    }
    let components = Calendar.autoupdatingCurrent.dateComponents([.month, .day], from: date)
    guard let month = components.month, let day = components.day else {
        return dayKey
    }
    return language.text("\(month)/\(day)", "\(month)月\(day)日")
}

private func formatShortDayLabel(_ dayKey: String) -> String {
    guard let date = usageDayKeyFormatter.date(from: dayKey) else {
        return dayKey
    }
    return usageDisplayDayFormatter.string(from: date)
}

private func formatCompactDuration(_ milliseconds: Int, language: InterfaceLanguage) -> String {
    guard milliseconds > 0 else {
        return language.text("0m", "0分")
    }

    let totalMinutes = Int((Double(milliseconds) / 60_000).rounded())
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60

    if hours > 0 {
        return language.text("\(hours)h \(minutes)m", "\(hours)小时\(minutes)分")
    }
    return language.text("\(minutes)m", "\(minutes)分")
}

private func formatDuration(_ milliseconds: Int, language: InterfaceLanguage) -> String {
    guard milliseconds > 0 else {
        return language.text("0 minutes", "0 分钟")
    }

    let totalMinutes = Int((Double(milliseconds) / 60_000).rounded())
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60

    if hours > 0 && minutes > 0 {
        return language.text("\(hours)h \(minutes)m", "\(hours)小时 \(minutes)分钟")
    }
    if hours > 0 {
        return language.text("\(hours)h", "\(hours)小时")
    }
    return language.text("\(minutes)m", "\(minutes)分钟")
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
