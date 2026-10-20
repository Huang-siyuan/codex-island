import AppKit
import Combine

/// 管理面板生命周期；所有面板共享数据，轮询和通知只在 AppDelegate 执行一次。
@MainActor
final class IslandPanelCoordinator {
    private let viewModel: IslandViewModel
    private let screenLocator: ActiveScreenLocator
    private let preferences: IslandDisplayPreferences
    private var panels: [IslandPanelController] = []
    private var modeSubscription: AnyCancellable?
    private var isClosed = false

    init(viewModel: IslandViewModel, screenLocator: ActiveScreenLocator, preferences: IslandDisplayPreferences) {
        self.viewModel = viewModel
        self.screenLocator = screenLocator
        self.preferences = preferences
        modeSubscription = preferences.$mode.dropFirst().sink { [weak self] _ in
            // 等 Picker 完成选择并写入新值后再调整窗口，保留正在操作的面板。
            Task { @MainActor [weak self] in
                self?.reconcilePanels()
            }
        }
    }

    func reconcilePanels(on screens: [NSScreen] = NSScreen.screens) {
        guard !isClosed else {
            return
        }
        let screenIDs = screens.compactMap(\.islandDisplayID)
        guard !screenIDs.isEmpty else {
            panels.forEach { $0.close() }
            panels.removeAll()
            return
        }

        switch preferences.mode {
        case .followFocus:
            let retained = panels.first(where: \.isKeyWindow)
                ?? panels.first { $0.currentScreenID == screenLocator.activeScreen()?.islandDisplayID }
                ?? panels.first
                ?? makePanel(displayID: nil)
            panels.filter { $0 !== retained }.forEach { $0.close() }
            retained.displayID = nil
            panels = [retained]
        case .everyScreen:
            // 首次切换时复用跟随面板，设置页与当前展开状态保持不变。
            for panel in panels where panel.displayID == nil {
                panel.displayID = panel.currentScreenID ?? screenIDs.first
            }
            let removed = panels.filter { panel in
                !screenIDs.contains { $0 == panel.displayID }
            }
            removed.forEach { $0.close() }
            panels.removeAll { panel in
                !screenIDs.contains { $0 == panel.displayID }
            }
            for screenID in screenIDs where !panels.contains(where: { $0.displayID == screenID }) {
                panels.append(makePanel(displayID: screenID))
            }
        }
        panels.forEach { $0.refreshPosition() }
    }

    func refreshFocusedPositionIfNeeded() {
        guard preferences.mode == .followFocus else {
            return
        }
        panels.first?.refreshPositionIfScreenChanged()
    }

    func close() {
        isClosed = true
        modeSubscription = nil
        panels.forEach { $0.close() }
        panels.removeAll()
    }

    private func makePanel(displayID: CGDirectDisplayID?) -> IslandPanelController {
        IslandPanelController(
            viewModel: viewModel,
            screenLocator: screenLocator,
            displayPreferences: preferences,
            displayID: displayID
        )
    }
}
