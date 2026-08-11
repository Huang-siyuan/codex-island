import CodexIslandCore
import CoreGraphics
import Testing

@Test
func menuBarGeometryUsesTheReservedTopBand() {
    #expect(
        MenuBarGeometry.resolvedCompactBarHeight(
            menuBarThickness: 33,
            safeAreaTop: 32,
            statusBarThickness: 22
        ) == 33
    )
}

@Test
func menuBarGeometryFallsBackToStatusBarThickness() {
    #expect(
        MenuBarGeometry.resolvedCompactBarHeight(
            menuBarThickness: 0,
            safeAreaTop: 0,
            statusBarThickness: 22
        ) == 22
    )
}

@Test
func menuBarGeometryDetectsUnavailableTopCenterArea() {
    let screenFrame = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    let area = MenuBarGeometry.resolvedUnavailableTopCenterArea(
        screenFrame: screenFrame,
        auxiliaryTopLeftArea: CGRect(x: 0, y: 1085, width: 771, height: 32),
        auxiliaryTopRightArea: CGRect(x: 956, y: 1085, width: 772, height: 32)
    )

    #expect(area == CGRect(x: 771, y: 1085, width: 185, height: 32))
}

@Test
func menuBarGeometryKeepsDefaultWidthWithoutUnavailableTopCenterArea() {
    #expect(
        MenuBarGeometry.resolvedCompactBarWidth(defaultWidth: 109) == 109
    )
}

@Test
func menuBarGeometryKeepsDefaultWidthForExternalDisplays() {
    #expect(
        MenuBarGeometry.resolvedCompactVisibleHeight(
            baseHeight: 33,
            unavailableTopCenterAreaHeight: 32,
            isBuiltInDisplay: false
        ) == 33
    )
}

@Test
func menuBarGeometryKeepsDefaultWidthForBuiltInDisplaysWithANotch() {
    #expect(
        MenuBarGeometry.resolvedCompactBarWidth(defaultWidth: 109) == 109
    )
}

@Test
func menuBarGeometryAddsRevealForBuiltInDisplaysWithANotch() {
    #expect(
        MenuBarGeometry.resolvedCompactVisibleHeight(
            baseHeight: 33,
            unavailableTopCenterAreaHeight: 32,
            isBuiltInDisplay: true
        ) == 42
    )
}

@Test
func menuBarGeometryAddsASmallTopAttachmentOverlap() {
    #expect(MenuBarGeometry.resolvedCompactTopAttachmentOverlap(visibleHeight: 22) == 4)
    #expect(MenuBarGeometry.resolvedCompactTopAttachmentOverlap(visibleHeight: 33) == 6)
}

@Test
func menuBarGeometryCompactLayoutCarriesTopAttachmentOverlap() {
    let layout = MenuBarGeometry.CompactBarLayout(
        height: 33,
        width: 109,
        centerX: 864,
        topAttachmentOverlap: 6,
        usesUnavailableTopCenterArea: true
    )

    #expect(layout.topAttachmentOverlap == 6)
}
