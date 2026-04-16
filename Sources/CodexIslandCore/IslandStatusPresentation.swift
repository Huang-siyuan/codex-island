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
    public static let preferredCompactWidth: CGFloat = resolvedCompactWidth(forLabelWidths: compactCandidateLabels.map(measureCompactLabelWidth))

    public static func compactLabelText(for statusText: String) -> String {
        switch statusText {
        case "Tool active":
            return "Tool active"
        case "Running":
            return "Running"
        case "Done":
            return "Watching"
        default:
            return "Watching"
        }
    }

    public static func compactBadgeText(for statusText: String) -> String {
        compactLabelText(for: statusText)
    }

    public static func resolvedCompactWidth(forLabelWidths labelWidths: [CGFloat]) -> CGFloat {
        let widestLabel = labelWidths.max() ?? 0
        let contentWidth = compactIndicatorSize + compactItemSpacing + widestLabel
        return ceil(contentWidth + (compactHorizontalPadding * 2) + 8)
    }

    public static func compactTone(for statusText: String) -> IslandStatusTone {
        switch statusText {
        case "Tool active":
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
    ]

    private static func measureCompactLabelWidth(_ text: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: compactFontSize, weight: .semibold),
        ]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }
}
