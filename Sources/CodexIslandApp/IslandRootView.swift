import CodexIslandCore
import SwiftUI

struct IslandRootView: View {
    @ObservedObject var viewModel: IslandViewModel
    var onMeasuredGeometryChange: (CGSize, CGFloat) -> Void = { _, _ in }

    private let expandedWidth: CGFloat = 760

    @State private var isExpanded = false
    @State private var lastReportedSize: CGSize = .zero
    @State private var lastReportedTopAttachmentOverlap: CGFloat = -.greatestFiniteMagnitude

    var body: some View {
        islandCard
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
            } else {
                collapsedHeader
            }

            if isExpanded {
                if let setupMessage = viewModel.setupMessage {
                    Label(setupMessage, systemImage: "wand.and.stars")
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
        .padding(.horizontal, isExpanded ? 16 : IslandStatusPresentation.compactHorizontalPadding)
        .padding(.vertical, isExpanded ? 14 : 0)
        .frame(width: isExpanded ? expandedWidth : compactShellWidth, alignment: .leading)
        .frame(height: isExpanded ? nil : compactShellHeight, alignment: .center)
        .fixedSize(horizontal: false, vertical: true)
        .compositingGroup()
        .background {
            shellShape.fill(shellGradient)
        }
        .overlay {
            shellShape
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        }
        .clipShape(shellShape)
        .contentShape(shellShape)
        .foregroundStyle(.white)
        .animation(.spring(duration: 0.25), value: isExpanded)
        .onHover { hovering in
            isExpanded = hovering
        }
        .onTapGesture {
            guard !isExpanded else {
                return
            }
            isExpanded = true
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
                Text(viewModel.threadTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                Text(viewModel.latestToolSummary ?? viewModel.statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            HStack(spacing: 8) {
                soundToggleButton

                Text(sessionCountText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
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
        .help(viewModel.isSoundEnabled ? "Mute completion sound" : "Enable completion sound")
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
                                badge(text: preview.statusText, color: statusColor(for: preview.statusText).opacity(0.2))
                                badge(text: relativeAgeText(for: preview.updatedAt), color: .white.opacity(0.08))
                            }
                        }

                        if let userPreview = preview.userPreview, !userPreview.isEmpty {
                            Text("You: \(userPreview)")
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
            Text("Waiting for recent session previews")
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
        "\(viewModel.sessionPreviews.count)/\(max(viewModel.activeSessionCount, viewModel.sessionPreviews.count)) sessions"
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

    private var compactStatusText: String {
        IslandStatusPresentation.compactLabelText(for: viewModel.statusText)
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
            return "now"
        }
        if seconds < 3600 {
            return "\(seconds / 60)m"
        }
        if seconds < 86_400 {
            return "\(seconds / 3_600)h"
        }
        return "\(seconds / 86_400)d"
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
