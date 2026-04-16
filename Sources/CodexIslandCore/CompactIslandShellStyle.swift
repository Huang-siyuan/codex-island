import Foundation

public struct CompactIslandShellMetrics: Equatable, Sendable {
    public let topCornerRadius: CGFloat
    public let bottomCornerRadius: CGFloat
    public let shoulderInset: CGFloat
    public let shoulderDepth: CGFloat

    public init(
        topCornerRadius: CGFloat,
        bottomCornerRadius: CGFloat,
        shoulderInset: CGFloat,
        shoulderDepth: CGFloat
    ) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.shoulderInset = shoulderInset
        self.shoulderDepth = shoulderDepth
    }
}

public enum CompactIslandShellStyle {
    public static func metrics(forHeight height: CGFloat) -> CompactIslandShellMetrics {
        let normalizedHeight = max(28, ceil(height))
        let topCornerRadius = max(7, min(11, round(normalizedHeight * 0.25)))
        let bottomCornerRadius = max(topCornerRadius + 5, min(17, round(normalizedHeight * 0.45)))
        let shoulderInset: CGFloat = 0
        let shoulderDepth = max(topCornerRadius + 2, min(12, round(normalizedHeight * 0.30)))
        return CompactIslandShellMetrics(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: bottomCornerRadius,
            shoulderInset: shoulderInset,
            shoulderDepth: shoulderDepth
        )
    }
}
