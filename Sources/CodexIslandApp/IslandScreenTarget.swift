import AppKit

@MainActor
final class IslandScreenTarget {
    private let screenLocator: ActiveScreenLocator
    var displayID: CGDirectDisplayID?

    init(screenLocator: ActiveScreenLocator, displayID: CGDirectDisplayID?) {
        self.screenLocator = screenLocator
        self.displayID = displayID
    }

    var screen: NSScreen? {
        if let displayID {
            return NSScreen.screens.first { $0.islandDisplayID == displayID }
        }
        return screenLocator.activeScreen()
    }
}

extension NSScreen {
    var islandDisplayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
