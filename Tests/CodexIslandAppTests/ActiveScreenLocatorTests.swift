@testable import CodexIslandApp
import CoreGraphics
import Foundation
import Testing

@MainActor
struct ActiveScreenLocatorTests {
    private let applicationPID: pid_t = 42
    private let primaryScreen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let leftScreen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)

    @Test
    func followsSmallerFrontWindowInsteadOfLargerBackgroundWindow() {
        let smallWindow = CGRect(x: -1600, y: 100, width: 500, height: 400)
        let largeWindow = CGRect(x: 100, y: 100, width: 1600, height: 900)
        let bounds = ActiveScreenLocator.frontmostWindowBounds(
            for: applicationPID,
            in: [window(smallWindow), window(largeWindow)]
        )
        #expect(bounds == smallWindow)
        #expect(ActiveScreenLocator.screenIndex(for: bounds!, screenFrames: [primaryScreen, leftScreen]) == 1)
    }

    @Test
    func followsWindowOrderChangesWithoutApplicationActivation() {
        let primaryWindow = CGRect(x: 100, y: 100, width: 600, height: 400)
        let leftWindow = CGRect(x: -1600, y: 100, width: 600, height: 400)
        for (windows, expectedScreen) in [
            ([window(primaryWindow), window(leftWindow)], 0),
            ([window(leftWindow), window(primaryWindow)], 1),
            ([window(primaryWindow), window(leftWindow)], 0),
        ] {
            let bounds = ActiveScreenLocator.frontmostWindowBounds(for: applicationPID, in: windows)
            #expect(ActiveScreenLocator.screenIndex(for: bounds!, screenFrames: [primaryScreen, leftScreen]) == expectedScreen)
        }
    }

    @Test
    func ignoresOtherApplicationsOverlaysTransparentAndTinyWindows() {
        let normalWindow = CGRect(x: 100, y: 100, width: 800, height: 600)
        let bounds = ActiveScreenLocator.frontmostWindowBounds(for: applicationPID, in: [
            [:],
            window(leftScreen, ownerPID: 99),
            window(leftScreen, layer: 25),
            window(leftScreen, alpha: 0),
            window(CGRect(x: -1000, y: 100, width: 50, height: 40)),
            window(normalWindow),
        ])
        #expect(bounds == normalWindow)
        #expect(ActiveScreenLocator.frontmostWindowBounds(for: applicationPID, in: []) == nil)
    }

    @Test
    func followsWindowDraggedBetweenScreens() {
        for (x, expectedScreen) in [(100.0, 0), (-1700.0, 1)] {
            let bounds = CGRect(x: x, y: 100, width: 800, height: 600)
            #expect(ActiveScreenLocator.screenIndex(for: bounds, screenFrames: [primaryScreen, leftScreen]) == expectedScreen)
        }
    }

    @Test
    func supportsDisplaysAbovePrimaryAndWindowsAcrossDisplayEdges() {
        let upperScreen = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        #expect(ActiveScreenLocator.screenIndex(
            for: CGRect(x: 100, y: -900, width: 800, height: 600),
            screenFrames: [primaryScreen, upperScreen]
        ) == 1)
        #expect(ActiveScreenLocator.screenIndex(
            for: CGRect(x: -200, y: 100, width: 800, height: 600),
            screenFrames: [primaryScreen, leftScreen]
        ) == 0)
    }

    @Test
    func convertsAppKitFramesRelativeToPrimaryDisplay() {
        let upperScreen = CGRect(x: 0, y: 1080, width: 1920, height: 1200)
        #expect(ActiveScreenLocator.quartzFrame(for: primaryScreen, primaryScreenFrame: primaryScreen) == primaryScreen)
        #expect(ActiveScreenLocator.quartzFrame(for: upperScreen, primaryScreenFrame: primaryScreen) ==
                CGRect(x: 0, y: -1200, width: 1920, height: 1200))
        #expect(ActiveScreenLocator.quartzFrame(for: leftScreen, primaryScreenFrame: primaryScreen) == leftScreen)
    }

    @Test
    func choosesLargestOverlapWhenCenterIsOutsideDisplays() {
        let shortScreen = CGRect(x: 0, y: 0, width: 500, height: 500)
        let tallScreen = CGRect(x: 600, y: 0, width: 500, height: 1200)
        #expect(ActiveScreenLocator.screenIndex(
            for: CGRect(x: 0, y: 400, width: 1100, height: 400),
            screenFrames: [shortScreen, tallScreen]
        ) == 1)
        #expect(ActiveScreenLocator.screenIndex(
            for: CGRect(x: 3000, y: 3000, width: 800, height: 600),
            screenFrames: [primaryScreen, leftScreen]
        ) == nil)
        #expect(ActiveScreenLocator.screenIndex(for: primaryScreen, screenFrames: []) == nil)
    }

    private func window(
        _ bounds: CGRect,
        ownerPID: pid_t? = nil,
        layer: Int = 0,
        alpha: Double = 1
    ) -> [String: Any] {
        [
            kCGWindowOwnerPID as String: NSNumber(value: ownerPID ?? applicationPID),
            kCGWindowLayer as String: NSNumber(value: layer),
            kCGWindowAlpha as String: NSNumber(value: alpha),
            kCGWindowBounds as String: bounds.dictionaryRepresentation,
        ]
    }
}
