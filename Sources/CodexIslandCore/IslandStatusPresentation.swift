import AppKit
import Foundation

public enum IslandStatusTone: String, Sendable, Equatable {
    case passive
    case running
    case tool
    case completed
}

public enum IslandStatusPresentation {
    public static let compactFontSize: CGFloat = 12
    public static let compactIndicatorSize: CGFloat = 7
    public static let compactItemSpacing: CGFloat = 6
    public static let compactHorizontalPadding: CGFloat = 12
    public static let compactUnreadSeparatorWidth: CGFloat = 1
    public static let compactUnreadSeparatorHeight: CGFloat = 12
    public static let compactUnreadReservedWidth = measureCompactLabelWidth("99 unread")
    public static let preferredCompactWidth: CGFloat = resolvedCompactWidth(forLabelWidths: compactCandidateLabels.map(measureCompactLabelWidth))

    public static func compactLabelText(for statusText: String) -> String {
        InterfaceLanguage.english.compactStatusText(for: statusText)
    }

    public static func compactLabelText(for statusText: String, language: InterfaceLanguage) -> String {
        language.compactStatusText(for: statusText)
    }

    public static func compactBadgeText(for statusText: String) -> String {
        compactLabelText(for: statusText)
    }

    public static func resolvedCompactWidth(
        forLabelWidths labelWidths: [CGFloat],
        unreadLabelWidth: CGFloat = compactUnreadReservedWidth
    ) -> CGFloat {
        let widestLabel = labelWidths.max() ?? 0
        // Reserve room for ordinary counts; grow for longer counts instead of clipping text.
        let contentWidth = compactIndicatorSize + compactItemSpacing + widestLabel
            + compactItemSpacing + compactUnreadSeparatorWidth + compactItemSpacing + unreadLabelWidth
        return ceil(contentWidth + (compactHorizontalPadding * 2) + 8)
    }

    public static func unreadText(count: Int?, language: InterfaceLanguage) -> String? {
        guard let count, count > 0 else {
            return nil
        }
        return language.text("\(count) unread", "\(count) 未读")
    }

    public static func compactWidth(unreadCount: Int?, language: InterfaceLanguage) -> CGFloat {
        let textWidth = unreadText(count: unreadCount, language: language).map(measureCompactLabelWidth) ?? 0
        return resolvedCompactWidth(
            forLabelWidths: compactCandidateLabels.map(measureCompactLabelWidth),
            unreadLabelWidth: max(compactUnreadReservedWidth, textWidth)
        )
    }

    public static func unreadAccessibilityLabel(count: Int?, language: InterfaceLanguage) -> String {
        guard let count else {
            return language.text("Codex unread status unavailable", "Codex 未读状态暂不可用")
        }
        return language.text(
            "\(count) unread Codex conversations",
            "\(count) 个 Codex 会话未读"
        )
    }

    public static func compactTone(for statusText: String) -> IslandStatusTone {
        switch statusText {
        case "Tool active", "Waiting for input":
            return .tool
        case "Running":
            return .running
        case "Done":
            return .passive
        default:
            return .passive
        }
    }

    private static let compactCandidateLabels = [
        "Watching",
        "Running",
        "Tool active",
        "Input needed",
    ]

    private static func measureCompactLabelWidth(_ text: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: compactFontSize, weight: .semibold),
        ]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }
}
