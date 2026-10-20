import AppKit
import CodexIslandCore
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let focusRouter = FocusRouter()
    private let firstLaunchSetup = FirstLaunchSetup()
    private let pollingEngine = PollingEngine()
    private let usageSnapshotLoader = UsageSnapshotLoader()
    private let screenLocator = ActiveScreenLocator()
    private let soundPreferenceStore = SoundPreferenceStore()

    private lazy var notificationManager = NotificationManager(soundPreferenceStore: soundPreferenceStore)
    private lazy var viewModel = IslandViewModel(
        focusRouter: focusRouter,
        soundPreferenceStore: soundPreferenceStore
    )
    private var panelController: IslandPanelController?
    private var pollingTask: Task<Void, Never>?
    private var positionTrackingTask: Task<Void, Never>?
    private var usageSnapshotTask: Task<Void, Never>?
    private var workspaceActivationObserver: NSObjectProtocol?
    private var screenParametersObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        screenLocator.noteActivatedApplication(NSWorkspace.shared.frontmostApplication)
        panelController = IslandPanelController(viewModel: viewModel, screenLocator: screenLocator)
        viewModel.onUsageRequested = { [weak self] in
            self?.loadUsageSnapshotIfNeeded()
        }
        viewModel.onUsageRefreshRequested = { [weak self] in
            self?.loadUsageSnapshotIfNeeded(forceRefresh: true)
        }
        Task { [weak self] in
            guard let self,
                  await usageSnapshotLoader.needsRefreshForCurrentDay() else {
                return
            }
            loadUsageSnapshotIfNeeded()
        }
        panelController?.show()
        installPositionObservers()
        scheduleLaunchReposition()

        Task { @MainActor in
            await notificationManager.requestAuthorization()
            let result = try? firstLaunchSetup.performIfNeeded()
            viewModel.showSetupResult(result)
        }

        pollingTask = Task { [weak self] in
            await self?.runSnapshotRefreshLoop()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollingTask?.cancel()
        usageSnapshotTask?.cancel()
        positionTrackingTask?.cancel()
        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver)
        }
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
        }
    }

    private func runSnapshotRefreshLoop() async {
        while !Task.isCancelled {
            let result = await pollingEngine.pollOnce()
            viewModel.apply(snapshot: result.snapshot)
            if viewModel.unreadCodexThreadCount != result.unreadCodexThreadCount {
                viewModel.unreadCodexThreadCount = result.unreadCodexThreadCount
            }

            if let request = result.userInputNotification {
                notificationManager.notifyUserInputRequested()
                await pollingEngine.consumeUserInputNotification(for: request)
            }

            if let completion = result.completionNotification {
                notificationManager.notifyCompletion(
                    provider: completion.provider,
                    threadID: completion.threadID,
                    threadTitle: completion.threadTitle
                )
                await pollingEngine.consumeCompletionNotification(for: completion.provider, threadID: completion.threadID)
            }

            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func loadUsageSnapshotIfNeeded(forceRefresh: Bool = false) {
        guard usageSnapshotTask == nil else {
            return
        }

        viewModel.isUsageRefreshing = true
        usageSnapshotTask = Task(priority: .background) { [weak self] in
            guard let self else {
                return
            }
            defer {
                viewModel.isUsageRefreshing = false
                usageSnapshotTask = nil
            }
            if let cachedSnapshot = await usageSnapshotLoader.cached() {
                viewModel.applyUsageSnapshot(cachedSnapshot)
            }
            let snapshot = await usageSnapshotLoader.snapshot(forceRefresh: forceRefresh)
            guard !Task.isCancelled else {
                return
            }
            viewModel.applyUsageSnapshot(snapshot)
        }
    }

    private func installPositionObservers() {
        // 同一应用切换窗口不会发出应用激活通知；独立检测，避免被会话读取拖慢。
        // 仅多屏时读取窗口列表，屏幕不变时不重新布局或置前，也不需要辅助功能授权。
        positionTrackingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(300))
                } catch {
                    return
                }
                guard let self else {
                    return
                }
                if NSScreen.screens.count > 1 {
                    panelController?.refreshPositionIfScreenChanged()
                }
            }
        }

        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.screenLocator.noteActivatedApplication(NSWorkspace.shared.frontmostApplication)
                self?.panelController?.refreshPosition()
            }
        }

        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.panelController?.refreshPosition()
            }
        }
    }

    private func scheduleLaunchReposition() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            self?.panelController?.show()
        }
    }
}
