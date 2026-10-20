import CodexIslandCore
import SwiftUI

/// 每个面板独立维护导航与屏幕几何，会话和通知数据仍由共享 ViewModel 提供。
@MainActor
final class IslandPanelState: ObservableObject {
    @Published var selectedExpandedTab: IslandExpandedTab = .sessions
    @Published var usageMetric: UsageDashboardMetric = .tokens
    @Published var compactBarHeight: CGFloat = 32
    @Published var compactBarWidth: CGFloat = IslandStatusPresentation.minimumCompactWidth
    @Published var compactTopAttachmentOverlap: CGFloat = MenuBarGeometry.resolvedCompactTopAttachmentOverlap(
        visibleHeight: 32
    )

    @discardableResult
    func updateCompactBarLayout(_ layout: MenuBarGeometry.CompactBarLayout) -> Bool {
        let normalizedHeight = max(22, ceil(layout.height))
        let normalizedWidth = max(IslandStatusPresentation.minimumCompactWidth, ceil(layout.width))
        let normalizedTopAttachmentOverlap = max(0, ceil(layout.topAttachmentOverlap))

        let heightChanged = abs(compactBarHeight - normalizedHeight) > 0.5
        let widthChanged = abs(compactBarWidth - normalizedWidth) > 0.5
        let topAttachmentChanged = abs(compactTopAttachmentOverlap - normalizedTopAttachmentOverlap) > 0.5

        guard heightChanged || widthChanged || topAttachmentChanged else {
            return false
        }

        if heightChanged {
            compactBarHeight = normalizedHeight
        }
        if widthChanged {
            compactBarWidth = normalizedWidth
        }
        if topAttachmentChanged {
            compactTopAttachmentOverlap = normalizedTopAttachmentOverlap
        }
        return true
    }
}
