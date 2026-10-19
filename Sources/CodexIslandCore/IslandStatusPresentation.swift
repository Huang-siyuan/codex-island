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
    public static let minimumCompactWidth = resolvedCompactWidth(statusLabelWidth: 0)

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
        statusLabelWidth: CGFloat,
        unreadLabelWidth: CGFloat? = nil
    ) -> CGFloat {
        var contentWidth = compactIndicatorSize + compactItemSpacing + statusLabelWidth
        if let unreadLabelWidth {
            contentWidth += compactItemSpacing + compactUnreadSeparatorWidth + compactItemSpacing + unreadLabelWidth
        }
        return ceil(contentWidth + (compactHorizontalPadding * 2) + 8)
    }

    public static func unreadText(count: Int?, language: InterfaceLanguage) -> String? {
        guard let count, count > 0 else {
            return nil
        }
        return language.text("\(count) unread", "\(count) 未读")
    }

    public static func compactWidth(statusText: String, unreadCount: Int?, language: InterfaceLanguage) -> CGFloat {
        // Match the visible localized status and the control font's monospaced digits.
        // Missing unread text also removes the separator and both adjacent gaps.
        let unreadWidth = unreadText(count: unreadCount, language: language).map {
            measureCompactLabelWidth($0, font: .monospacedDigitSystemFont(ofSize: 11, weight: .semibold))
        }
        return resolvedCompactWidth(
            statusLabelWidth: measureCompactLabelWidth(compactLabelText(for: statusText, language: language)),
            unreadLabelWidth: unreadWidth
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

    private static func measureCompactLabelWidth(
        _ text: String,
        font: NSFont = .systemFont(ofSize: compactFontSize, weight: .semibold)
    ) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
        ]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }
}
