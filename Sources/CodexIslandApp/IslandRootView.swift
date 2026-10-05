import CodexIslandCore
import SwiftUI

struct IslandRootView: View {
    @ObservedObject var viewModel: IslandViewModel
    var isPointerInsideWindow: () -> Bool = { false }
    var onMeasuredGeometryChange: (CGSize, CGFloat) -> Void = { _, _ in }

    private let shellExpandAnimation = Animation.spring(response: 0.34, dampingFraction: 0.84)
    private let shellCollapseAnimation = Animation.spring(response: 0.30, dampingFraction: 0.86)
    private let detailRevealAnimation = Animation.spring(response: 0.24, dampingFraction: 0.88)
    private let detailHideAnimation = Animation.easeOut(duration: 0.18)

    @State private var isExpanded = false
    @State private var showsExpandedContent = false
    @State private var detailRevealTask: Task<Void, Never>?
    @State private var lastReportedSize: CGSize = .zero
    @State private var lastReportedTopAttachmentOverlap: CGFloat = -.greatestFiniteMagnitude
    @AppStorage("interfaceLanguage") private var interfaceLanguageRaw = InterfaceLanguage.english.rawValue
    @AppStorage("islandAppearance") private var islandAppearanceRaw = IslandAppearance.classic.rawValue

    var body: some View {
        islandCard
            .environment(\.locale, language.locale)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            reportMeasuredGeometry(proxy.size)
                        }
                        .onChange(of: proxy.size) { _, newSize in
                            reportMeasuredGeometry(newSize)
                        }
                }
            }
    }

    private var islandCard: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 16 : 0) {
            if isExpanded {
                expandedHeader
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        )
                    )
            } else {
                collapsedHeader
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }

            if isExpanded, showsExpandedContent {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, isExpanded ? 16 : IslandStatusPresentation.compactHorizontalPadding)
        .padding(.vertical, isExpanded ? 14 : 0)
        .frame(width: isExpanded ? expandedWidth : compactShellWidth, alignment: .leading)
        .frame(height: isExpanded ? nil : compactShellHeight, alignment: .center)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            shellBackground
        }
        .overlay {
            shellBorder
        }
        .clipShape(shellShape)
        .contentShape(Rectangle())
        .foregroundStyle(.white)
        .onHover { hovering in
            handleHoverChange(hovering)
        }
        .animation(shellExpandAnimation, value: viewModel.selectedExpandedTab)
        .animation(shellExpandAnimation, value: interfaceLanguageRaw)
        .animation(.easeInOut(duration: 0.22), value: islandAppearanceRaw)
        .onTapGesture {
            guard !isExpanded else {
                return
            }
            expandIsland()
        }
        .onDisappear {
            detailRevealTask?.cancel()
        }
    }

    private var collapsedHeader: some View {
        HStack(alignment: .center, spacing: IslandStatusPresentation.compactItemSpacing) {
            Circle()
                .fill(compactStatusColor)
                .frame(width: IslandStatusPresentation.compactIndicatorSize, height: IslandStatusPresentation.compactIndicatorSize)

            Text(compactStatusText)
                .font(.system(size: IslandStatusPresentation.compactFontSize, weight: .semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .offset(y: compactTopAttachmentOverlap / 2)
    }

    private var expandedHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(localizedThreadTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .layoutPriority(1)

                Text(viewModel.latestToolSummary ?? language.statusText(for: viewModel.statusText))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            HStack(spacing: 8) {
                expandedTabPicker
                languageToggleButton
                soundToggleButton
                customSoundButton
                if viewModel.customCompletionSoundName != nil {
                    clearCustomSoundButton
                }

                Text(sessionCountText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            appearanceSelector

            Group {
                switch viewModel.selectedExpandedTab {
                case .sessions:
                    sessionsContent
                case .usage:
                    usageContent
                }
            }
        }
    }

    private var sessionsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let setupMessage = viewModel.setupMessage {
                Label(localizedSetupMessage(setupMessage), systemImage: "wand.and.stars")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(viewModel.sessionPreviews) { preview in
                    sessionPreviewCard(preview)
                }
                if viewModel.sessionPreviews.isEmpty {
                    emptyState
                }
            }
        }
    }

    private var usageContent: some View {
        UsageDashboardView(
            metric: $viewModel.usageMetric,
            snapshot: viewModel.usageSnapshot,
            language: language,
            appearance: appearance,
            isRefreshing: viewModel.isUsageRefreshing,
            onRefresh: viewModel.requestUsageRefresh
        )
        .onAppear {
            viewModel.refreshUsageIfSelected()
        }
    }

    private var expandedTabPicker: some View {
        HStack(spacing: 6) {
            ForEach(IslandExpandedTab.allCases) { tab in
                Button {
                    guard viewModel.selectedExpandedTab != tab else {
                        return
                    }
                    withAnimation(shellExpandAnimation) {
                        viewModel.selectExpandedTab(tab)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 10, weight: .semibold))

                        Text(tab.title(language: language))
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(viewModel.selectedExpandedTab == tab ? Color.white : Color.white.opacity(0.68))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        viewModel.selectedExpandedTab == tab
                            ? Color.white.opacity(0.12)
                            : Color.white.opacity(0.05),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                Color.white.opacity(viewModel.selectedExpandedTab == tab ? 0.09 : 0.04),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }

        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var appearanceSelector: some View {
        HStack(spacing: 10) {
            Label(language.text("Appearance", "外观"), systemImage: "paintbrush.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.58))

            Spacer()

            HStack(spacing: 4) {
                ForEach(IslandAppearance.allCases) { option in
                    Button {
                        islandAppearanceRaw = option.rawValue
                    } label: {
                        Text(option.title(language: language))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(option == appearance ? Color.white : Color.white.opacity(0.60))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                option == appearance ? Color.white.opacity(0.13) : Color.clear,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(option == appearance ? .isSelected : [])
                }
            }
            .padding(3)
            .background(Color.white.opacity(0.045), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        }
        .padding(.horizontal, 2)
    }

    private var languageToggleButton: some View {
        Button {
            interfaceLanguageRaw = language == .english
                ? InterfaceLanguage.simplifiedChinese.rawValue
                : InterfaceLanguage.english.rawValue
        } label: {
            Text(language.toggleTitle)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.86))
                .frame(width: 26, height: 22)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(language.text("Switch to Chinese", "切换到英文"))
        .accessibilityLabel(language.text("Switch interface language to Chinese", "将界面语言切换为英文"))
    }

    private var soundToggleButton: some View {
        Button {
            viewModel.toggleSoundEnabled()
        } label: {
            Image(systemName: viewModel.isSoundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(viewModel.isSoundEnabled ? Color.white.opacity(0.9) : Color.white.opacity(0.6))
                .frame(width: 26, height: 22)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(
            viewModel.isSoundEnabled
                ? language.text("Mute completion sound", "关闭完成提示音")
                : language.text("Enable completion sound", "开启完成提示音")
        )
    }

    private var customSoundButton: some View {
        Button {
            viewModel.chooseCustomCompletionSound(language: language)
        } label: {
            Image(systemName: viewModel.customCompletionSoundName == nil ? "music.note" : "music.note.list")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(viewModel.customCompletionSoundName == nil ? Color.white.opacity(0.65) : Color.white.opacity(0.92))
                .frame(width: 26, height: 22)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(
            viewModel.customCompletionSoundName.map {
                language.text("Custom completion sound: \($0)", "自定义完成提示音：\($0)")
            } ?? language.text("Choose custom completion sound", "选择自定义完成提示音")
        )
    }

    private var clearCustomSoundButton: some View {
        Button {
            viewModel.clearCustomCompletionSound()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.58))
                .frame(width: 22, height: 22)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.04), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(language.text("Use default completion sound", "使用默认完成提示音"))
    }

    private func sessionPreviewCard(_ preview: SessionPreview) -> some View {
        Button {
            viewModel.openSession(preview)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(statusColor(for: preview.statusText))
                        .frame(width: 9, height: 9)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Text(preview.title)
                                .font(.system(size: 16, weight: .semibold))
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            HStack(spacing: 8) {
                                badge(text: preview.sourceLabel, color: .white.opacity(0.12))
                                badge(
                                    text: language.statusText(for: preview.statusText),
                                    color: statusColor(for: preview.statusText).opacity(0.2)
                                )
                                badge(text: relativeAgeText(for: preview.updatedAt), color: .white.opacity(0.08))
                            }
                        }

                        if let userPreview = preview.userPreview, !userPreview.isEmpty {
                            Text(language.text("You: \(userPreview)", "你：\(userPreview)"))
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.78))
                                .lineLimit(2)
                        }

                        if let assistantPreview = preview.assistantPreview ?? preview.latestToolSummary,
                           let renderedAssistantPreview = SessionPreviewMarkdownRenderer.render(assistantPreview) {
                            Text(renderedAssistantPreview)
                                .font(.system(size: 13, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color.white.opacity(0.94))
                                .lineLimit(2)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                preview.isPrimary ? Color.white.opacity(0.11) : Color.white.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(preview.isPrimary ? 0.08 : 0.04), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack")
                .foregroundStyle(.secondary)
            Text(language.text("Waiting for recent session previews", "正在等待最近的会话预览"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func badge(text: String, color: Color, fontSize: CGFloat = 11) -> some View {
        Text(text)
            .font(.system(size: fontSize, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color, in: Capsule())
    }

    private var sessionCountText: String {
        let count = "\(viewModel.sessionPreviews.count)/\(max(viewModel.activeSessionCount, viewModel.sessionPreviews.count))"
        return language.text("\(count) sessions", "\(count) 个会话")
    }

    private var statusColor: Color {
        statusColor(for: viewModel.statusText)
    }

    private var shellGradient: LinearGradient {
        LinearGradient(
            colors: [Color.black.opacity(0.96), Color(red: 0.10, green: 0.11, blue: 0.14)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private var shellBackground: some View {
        switch appearance {
        case .classic:
            shellShape.fill(shellGradient)
        case .macOSGlass:
            ZStack {
                MacOSVisualEffectView(material: .hudWindow)
                glassTintGradient
                glassHighlightGradient
            }
        }
    }

    @ViewBuilder
    private var shellBorder: some View {
        switch appearance {
        case .classic:
            shellShape.strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        case .macOSGlass:
            shellShape.strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.52),
                        Color.white.opacity(0.18),
                        Color(red: 0.30, green: 0.68, blue: 1.0).opacity(0.28),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
        }
    }

    private var glassTintGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.28, green: 0.10, blue: 0.44).opacity(0.22),
                Color(red: 0.08, green: 0.17, blue: 0.38).opacity(0.16),
                Color(red: 0.02, green: 0.34, blue: 0.72).opacity(0.20),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var glassHighlightGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.13),
                Color.clear,
                Color.black.opacity(0.08),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var expandedWidth: CGFloat {
        760
    }

    private var compactStatusText: String {
        IslandStatusPresentation.compactLabelText(for: viewModel.statusText, language: language)
    }

    private var compactVisibleHeight: CGFloat {
        max(22, ceil(viewModel.compactBarHeight))
    }

    private var compactTopAttachmentOverlap: CGFloat {
        isExpanded ? 0 : max(0, ceil(viewModel.compactTopAttachmentOverlap))
    }

    private var compactShellHeight: CGFloat {
        compactVisibleHeight + compactTopAttachmentOverlap
    }

    private var compactShellWidth: CGFloat {
        max(IslandStatusPresentation.preferredCompactWidth, ceil(viewModel.compactBarWidth))
    }

    private var compactShellMetrics: CompactIslandShellMetrics {
        CompactIslandShellStyle.metrics(forHeight: compactShellHeight)
    }

    private var compactStatusColor: Color {
        switch IslandStatusPresentation.compactTone(for: viewModel.statusText) {
        case .tool:
            return Color.orange
        case .running:
            return Color.yellow
        case .completed:
            return Color.green
        case .passive:
            return Color.gray
        }
    }

    private var shellShape: IslandShellShape {
        if isExpanded {
            return .expanded(cornerRadius: 28)
        }
        return .compact(
            topCornerRadius: compactShellMetrics.topCornerRadius,
            bottomCornerRadius: compactShellMetrics.bottomCornerRadius,
            shoulderInset: compactShellMetrics.shoulderInset,
            shoulderDepth: compactShellMetrics.shoulderDepth
        )
    }

    private func statusColor(for statusText: String) -> Color {
        switch statusText {
        case "Done":
            return Color.green
        case "Tool active":
            return Color.orange
        case "Running":
            return Color.yellow
        default:
            return Color.gray
        }
    }

    private func relativeAgeText(for date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 {
            return language.text("now", "刚刚")
        }
        if seconds < 3600 {
            return language.text("\(seconds / 60)m", "\(seconds / 60)分钟前")
        }
        if seconds < 86_400 {
            return language.text("\(seconds / 3_600)h", "\(seconds / 3_600)小时前")
        }
        return language.text("\(seconds / 86_400)d", "\(seconds / 86_400)天前")
    }

    private var language: InterfaceLanguage {
        InterfaceLanguage(rawValue: interfaceLanguageRaw) ?? .english
    }

    private var appearance: IslandAppearance {
        IslandAppearance(rawValue: islandAppearanceRaw) ?? .classic
    }

    private var localizedThreadTitle: String {
        guard viewModel.threadTitle == "Watching AI tools" else {
            return viewModel.threadTitle
        }
        return language.text(viewModel.threadTitle, "监看 AI 工具")
    }

    private func localizedSetupMessage(_ message: String) -> String {
        switch message {
        case "CLI helper installed and zsh updated":
            return language.text(message, "CLI 辅助工具已安装，并已更新 zsh")
        case "CLI helper installed":
            return language.text(message, "CLI 辅助工具已安装")
        default:
            return message
        }
    }

    private func reportMeasuredGeometry(_ size: CGSize) {
        let normalizedSize = CGSize(width: ceil(size.width), height: ceil(size.height))
        let normalizedTopAttachmentOverlap = compactTopAttachmentOverlap
        guard normalizedSize.width > 0, normalizedSize.height > 0 else {
            return
        }
        guard normalizedSize.width != lastReportedSize.width ||
            normalizedSize.height != lastReportedSize.height ||
            normalizedTopAttachmentOverlap != lastReportedTopAttachmentOverlap else {
            return
        }

        lastReportedSize = normalizedSize
        lastReportedTopAttachmentOverlap = normalizedTopAttachmentOverlap
        onMeasuredGeometryChange(normalizedSize, normalizedTopAttachmentOverlap)
    }

    private func handleHoverChange(_ hovering: Bool) {
        if hovering {
            expandIsland()
        } else {
            scheduleCollapse()
        }
    }

    private func expandIsland() {
        if !isExpanded {
            withAnimation(shellExpandAnimation) {
                isExpanded = true
            }
            // The selected tab survives collapse, so reopening Usage must request a fresh snapshot too.
            viewModel.refreshUsageIfSelected()
        }

        guard !showsExpandedContent, detailRevealTask == nil else {
            return
        }

        // Let the lightweight shell react first, then mount the larger detail tree.
        detailRevealTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(35))
            guard !Task.isCancelled, isExpanded else {
                detailRevealTask = nil
                return
            }
            withAnimation(detailRevealAnimation) {
                showsExpandedContent = true
            }
            detailRevealTask = nil
        }
    }

    private func scheduleCollapse() {
        // SwiftUI can emit a false hover-exit while replacing the tracking area.
        // Verify the real window frame synchronously so genuine exits collapse immediately.
        guard !isPointerInsideWindow() else {
            return
        }
        collapseIsland()
    }

    private func collapseIsland() {
        detailRevealTask?.cancel()
        detailRevealTask = nil
        withAnimation(shellCollapseAnimation) {
            showsExpandedContent = false
            isExpanded = false
        }
    }
}

private struct IslandShellShape: InsettableShape {
    enum Style {
        case expanded(cornerRadius: CGFloat)
        case compact(topCornerRadius: CGFloat, bottomCornerRadius: CGFloat, shoulderInset: CGFloat, shoulderDepth: CGFloat)
    }

    let style: Style
    var insetAmount: CGFloat = 0

    static func expanded(cornerRadius: CGFloat) -> IslandShellShape {
        IslandShellShape(style: .expanded(cornerRadius: cornerRadius))
    }

    static func compact(
        topCornerRadius: CGFloat,
        bottomCornerRadius: CGFloat,
        shoulderInset: CGFloat,
        shoulderDepth: CGFloat
    ) -> IslandShellShape {
        IslandShellShape(
            style: .compact(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius,
                shoulderInset: shoulderInset,
                shoulderDepth: shoulderDepth
            )
        )
    }

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard insetRect.width > 0, insetRect.height > 0 else {
            return Path()
        }

        switch style {
        case let .expanded(cornerRadius):
            return RoundedRectangle(
                cornerRadius: max(0, cornerRadius - insetAmount),
                style: .continuous
            ).path(in: insetRect)
        case let .compact(topCornerRadius, bottomCornerRadius, shoulderInset, shoulderDepth):
            return compactPath(
                in: insetRect,
                topCornerRadius: max(0, topCornerRadius - insetAmount),
                bottomCornerRadius: max(0, bottomCornerRadius - insetAmount),
                shoulderInset: max(0, shoulderInset - insetAmount),
                shoulderDepth: max(0, shoulderDepth - insetAmount)
            )
        }
    }

    func inset(by amount: CGFloat) -> IslandShellShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    private func compactPath(
        in rect: CGRect,
        topCornerRadius: CGFloat,
        bottomCornerRadius: CGFloat,
        shoulderInset: CGFloat,
        shoulderDepth: CGFloat
    ) -> Path {
        let limitedTopRadius = min(topCornerRadius, rect.width / 2, rect.height / 2)
        let limitedBottomRadius = min(bottomCornerRadius, rect.width / 2, rect.height / 2)
        let limitedShoulderInset = min(shoulderInset, max(0, (rect.width / 2) - limitedBottomRadius - 1))
        let limitedShoulderDepth = min(shoulderDepth, max(limitedTopRadius + 1, rect.height - limitedBottomRadius - 1))
        let rightShoulderX = rect.maxX - limitedShoulderInset
        let leftShoulderX = rect.minX + limitedShoulderInset
        let shoulderY = rect.minY + limitedShoulderDepth

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + limitedTopRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - limitedTopRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + limitedTopRadius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addCurve(
            to: CGPoint(x: rightShoulderX, y: shoulderY),
            control1: CGPoint(x: rect.maxX, y: rect.minY + limitedTopRadius + (limitedShoulderDepth * 0.35)),
            control2: CGPoint(x: rect.maxX - (limitedShoulderInset * 0.18), y: rect.minY + (limitedShoulderDepth * 0.88))
        )
        path.addLine(to: CGPoint(x: rightShoulderX, y: rect.maxY - limitedBottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: rightShoulderX - limitedBottomRadius, y: rect.maxY),
            control: CGPoint(x: rightShoulderX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: leftShoulderX + limitedBottomRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: leftShoulderX, y: rect.maxY - limitedBottomRadius),
            control: CGPoint(x: leftShoulderX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: leftShoulderX, y: shoulderY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + limitedTopRadius),
            control1: CGPoint(x: rect.minX + (limitedShoulderInset * 0.18), y: rect.minY + (limitedShoulderDepth * 0.88)),
            control2: CGPoint(x: rect.minX, y: rect.minY + limitedTopRadius + (limitedShoulderDepth * 0.35))
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + limitedTopRadius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
