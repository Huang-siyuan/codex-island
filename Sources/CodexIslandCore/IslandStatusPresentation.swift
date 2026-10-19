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
    public static let compactUnreadBadgeWidth: CGFloat = 24
    public static let compactUnreadBadgeHeight: CGFloat = 18
    public static let compactUnreadDisplayLimit = 9
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

    public static func resolvedCompactWidth(forLabelWidths labelWidths: [CGFloat]) -> CGFloat {
        let widestLabel = labelWidths.max() ?? 0
        // Reserve badge space even at zero to avoid resizing the shell as read state changes.
        let contentWidth = compactIndicatorSize + compactItemSpacing + widestLabel
            + compactItemSpacing + compactUnreadBadgeWidth
        return ceil(contentWidth + (compactHorizontalPadding * 2) + 8)
    }

    public static func unreadBadgeText(count: Int?) -> String? {
        guard let count, count > 0 else {
            return nil
        }
        return count > compactUnreadDisplayLimit ? "\(compactUnreadDisplayLimit)+" : String(count)
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
