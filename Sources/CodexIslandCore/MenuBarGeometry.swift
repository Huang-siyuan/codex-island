import AppKit
import Foundation

public enum MenuBarGeometry {
    public struct CompactBarLayout: Equatable {
        public let height: CGFloat
        public let width: CGFloat
        public let centerX: CGFloat
        public let topAttachmentOverlap: CGFloat
        public let usesUnavailableTopCenterArea: Bool

        public init(
            height: CGFloat,
            width: CGFloat,
            centerX: CGFloat,
            topAttachmentOverlap: CGFloat,
            usesUnavailableTopCenterArea: Bool
        ) {
            self.height = height
            self.width = width
            self.centerX = centerX
            self.topAttachmentOverlap = topAttachmentOverlap
            self.usesUnavailableTopCenterArea = usesUnavailableTopCenterArea
        }
    }

    public static func compactBarLayout(for screen: NSScreen, defaultWidth: CGFloat) -> CompactBarLayout {
        let unavailableTopCenterArea: CGRect?
        if #available(macOS 12.0, *) {
            unavailableTopCenterArea = resolvedUnavailableTopCenterArea(
                screenFrame: screen.frame,
                auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
                auxiliaryTopRightArea: screen.auxiliaryTopRightArea
            )
        } else {
            unavailableTopCenterArea = nil
        }

        return CompactBarLayout(
            height: compactBarHeight(for: screen),
            width: resolvedCompactBarWidth(
                defaultWidth: defaultWidth,
                unavailableTopCenterWidth: unavailableTopCenterArea?.width
            ),
            centerX: resolvedCompactBarCenterX(
                screenFrame: screen.frame,
                unavailableTopCenterArea: unavailableTopCenterArea
            ),
            topAttachmentOverlap: resolvedCompactTopAttachmentOverlap(
                visibleHeight: compactBarHeight(for: screen)
            ),
            usesUnavailableTopCenterArea: unavailableTopCenterArea != nil
        )
    }

    public static func compactBarHeight(for screen: NSScreen) -> CGFloat {
        let safeAreaTop: CGFloat
        if #available(macOS 12.0, *) {
            safeAreaTop = screen.safeAreaInsets.top
        } else {
            safeAreaTop = 0
        }

        return resolvedCompactBarHeight(
            menuBarThickness: screen.frame.maxY - screen.visibleFrame.maxY,
            safeAreaTop: safeAreaTop,
            statusBarThickness: NSStatusBar.system.thickness
        )
    }

    public static func resolvedCompactBarHeight(
        menuBarThickness: CGFloat,
        safeAreaTop: CGFloat,
        statusBarThickness: CGFloat
    ) -> CGFloat {
        let candidates = [
            max(0, menuBarThickness),
            max(0, safeAreaTop),
            max(0, statusBarThickness),
        ]
        return ceil(candidates.max() ?? statusBarThickness)
    }

    public static func resolvedUnavailableTopCenterArea(
        screenFrame: CGRect,
        auxiliaryTopLeftArea: CGRect?,
        auxiliaryTopRightArea: CGRect?
    ) -> CGRect? {
        guard let auxiliaryTopLeftArea, let auxiliaryTopRightArea else {
            return nil
        }

        let normalizedLeftArea = auxiliaryTopLeftArea.intersection(screenFrame)
        let normalizedRightArea = auxiliaryTopRightArea.intersection(screenFrame)
        guard !normalizedLeftArea.isNull, !normalizedRightArea.isNull else {
            return nil
        }

        let gapMinX = max(screenFrame.minX, normalizedLeftArea.maxX)
        let gapMaxX = min(screenFrame.maxX, normalizedRightArea.minX)
        let gapMinY = max(screenFrame.minY, normalizedLeftArea.minY, normalizedRightArea.minY)
        let gapMaxY = min(screenFrame.maxY, normalizedLeftArea.maxY, normalizedRightArea.maxY)

        let gapWidth = gapMaxX - gapMinX
        let gapHeight = gapMaxY - gapMinY
        guard gapWidth >= 60, gapHeight >= 12 else {
            return nil
        }

        return CGRect(x: gapMinX, y: gapMinY, width: gapWidth, height: gapHeight).integral
    }

    public static func resolvedCompactBarWidth(
        defaultWidth: CGFloat,
        unavailableTopCenterWidth: CGFloat?
    ) -> CGFloat {
        guard let unavailableTopCenterWidth, unavailableTopCenterWidth > 0 else {
            return ceil(defaultWidth)
        }

        return ceil(max(defaultWidth, min(defaultWidth + 12, unavailableTopCenterWidth + 18)))
    }

    public static func resolvedCompactBarCenterX(
        screenFrame: CGRect,
        unavailableTopCenterArea: CGRect?
    ) -> CGFloat {
        unavailableTopCenterArea?.midX ?? screenFrame.midX
    }

    public static func resolvedCompactTopAttachmentOverlap(visibleHeight: CGFloat) -> CGFloat {
        let normalizedHeight = max(22, ceil(visibleHeight))
        return ceil(min(6, max(4, normalizedHeight * 0.18)))
    }
}
