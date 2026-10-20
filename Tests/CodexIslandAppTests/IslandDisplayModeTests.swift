@testable import CodexIslandApp
import AppKit
import CodexIslandCore
import Foundation
import Testing

@MainActor
struct IslandDisplayModeTests {
    @Test
    func defaultsToFollowingFocusAndToleratesUnknownPreferences() {
        let name = "IslandDisplayModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(IslandDisplayPreferences(defaults: defaults).mode == .followFocus)
        defaults.set("unknown", forKey: IslandDisplayPreferences.defaultsKey)
        #expect(IslandDisplayPreferences(defaults: defaults).mode == .followFocus)
    }

    @Test
    func restoresBothModesAfterRecreatingPreferences() {
        let name = "IslandDisplayModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = IslandDisplayPreferences(defaults: defaults)
        for mode in [IslandDisplayMode.everyScreen, .followFocus] {
            preferences.mode = mode
            #expect(IslandDisplayPreferences(defaults: defaults).mode == mode)
        }
    }

    @Test
    func panelNavigationAndScreenGeometryRemainIndependent() {
        let first = IslandPanelState()
        let second = IslandPanelState()
        let originalHeight = second.compactBarHeight
        first.selectedExpandedTab = .settings
        first.usageMetric = .time
        first.updateCompactBarLayout(.init(
            height: 48, width: 240, centerX: 600,
            topAttachmentOverlap: 6, usesUnavailableTopCenterArea: true
        ))
        #expect(first.compactBarHeight == 48)
        #expect(second.compactBarHeight == originalHeight)
        #expect(second.selectedExpandedTab == .sessions)
        #expect(second.usageMetric == .tokens)
    }

    @Test
    func localizesBothDropdownOptions() {
        #expect(IslandDisplayMode.followFocus.title(language: .english) == "Follow focus")
        #expect(IslandDisplayMode.everyScreen.title(language: .english) == "One Island per screen")
        #expect(IslandDisplayMode.followFocus.title(language: .simplifiedChinese) == "跟随聚焦")
        #expect(IslandDisplayMode.everyScreen.title(language: .simplifiedChinese) == "每个屏幕一个刘海")
    }

    @Test
    func reconcilesRealPanelsOnModeAndScreenChanges() async throws {
        _ = NSApplication.shared
        let screens = NSScreen.screens
        guard let firstScreen = screens.first else {
            return
        }
        let name = "IslandDisplayModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = IslandDisplayPreferences(defaults: defaults)
        let coordinator = IslandPanelCoordinator(
            viewModel: IslandViewModel(
                focusRouter: FocusRouter(),
                soundPreferenceStore: SoundPreferenceStore(userDefaults: defaults)
            ),
            screenLocator: ActiveScreenLocator(),
            preferences: preferences
        )
        defer { coordinator.close() }

        coordinator.reconcilePanels()
        #expect(visiblePanels.count == 1)
        preferences.mode = .everyScreen
        // 验证真实订阅路径会自动增添面板，不依赖手动调用刷新。
        try await Task.sleep(for: .milliseconds(100))
        #expect(visiblePanels.count == screens.count)
        for screen in screens {
            let matches = visiblePanels.filter {
                abs($0.frame.midX - screen.frame.midX) < 2 && abs($0.frame.maxY - screen.frame.maxY) < 12
            }
            #expect(matches.count == 1)
        }
        let windowNumbers = Set(visiblePanels.map(\.windowNumber))
        coordinator.reconcilePanels()
        #expect(Set(visiblePanels.map(\.windowNumber)) == windowNumbers)

        // 注入屏幕快照，覆盖断开、重新连接和系统短暂返回空列表的生命周期。
        coordinator.reconcilePanels(on: [firstScreen])
        #expect(visiblePanels.count == 1)
        coordinator.reconcilePanels(on: [])
        #expect(visiblePanels.isEmpty)
        coordinator.reconcilePanels()
        #expect(visiblePanels.count == screens.count)
        preferences.mode = .followFocus
        try await Task.sleep(for: .milliseconds(100))
        #expect(visiblePanels.count == 1)
        preferences.mode = .everyScreen
        coordinator.close()
        try await Task.sleep(for: .milliseconds(100))
        #expect(visiblePanels.isEmpty)
    }

    private var visiblePanels: [NSWindow] {
        NSApp.windows.filter { $0.title == "Codex Island" && $0.isVisible }
    }
}
