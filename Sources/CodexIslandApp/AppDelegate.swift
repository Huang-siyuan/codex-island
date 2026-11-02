import AppKit
import CodexIslandCore
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let focusRouter = FocusRouter()
    private let firstLaunchSetup = FirstLaunchSetup()
    private let pollingEngine = PollingEngine()
    private let desktopClient = CodexDesktopClient()
    private let usageSnapshotLoader = UsageSnapshotLoader()
    private let screenLocator = ActiveScreenLocator()
    private let soundPreferenceStore = SoundPreferenceStore()

    private lazy var notificationManager = NotificationManager(soundPreferenceStore: soundPreferenceStore)
    private lazy var viewModel = IslandViewModel(
        focusRouter: focusRouter,
        soundPreferenceStore: soundPreferenceStore
    )
    private let displayPreferences = IslandDisplayPreferences()
    private lazy var panelCoordinator = IslandPanelCoordinator(
        viewModel: viewModel,
        screenLocator: screenLocator,
        preferences: displayPreferences
    )
    private var quotaTask: Task<Void, Never>?
    private var quotaRefreshTask: Task<Void, Never>?
    private var quotaAlerts = QuotaAlertTracker()
    private var pollingTask: Task<Void, Never>?
    private var positionTrackingTask: Task<Void, Never>?
    private var usageSnapshotTask: Task<Void, Never>?
    private var workspaceActivationObserver: NSObjectProtocol?
    private var screenParametersObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        screenLocator.noteActivatedApplication(NSWorkspace.shared.frontmostApplication)
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
        viewModel.onQuestionAnswer = { [weak self] request, answers in
            guard let self else { throw CodexLocalError.unavailable }
            try await desktopClient.answer(request, answers: answers)
        }
        viewModel.onQuotaRefreshRequested = { [weak self] in self?.refreshQuota() }
        quotaTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshQuota()
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
        panelCoordinator.reconcilePanels()
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
        panelCoordinator.close()
        Task { await desktopClient.close() }
        pollingTask?.cancel()
        quotaTask?.cancel()
        quotaRefreshTask?.cancel()
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
            var codexIDs = Set(result.snapshot.sessionPreviews.filter { $0.provider == .codex }.map(\.threadID))
            if let active = viewModel.pendingQuestions.first(where: { $0.id == viewModel.activeQuestionID || $0.id == viewModel.submittingQuestionID }) {
                codexIDs.insert(active.threadID)
            }
            viewModel.applyQuestions(await desktopClient.refresh(threadIDs: codexIDs))
            if viewModel.unreadCodexThreadIDs != result.unreadCodexThreadIDs {
                viewModel.unreadCodexThreadIDs = result.unreadCodexThreadIDs
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

    private func refreshQuota() {
        guard quotaRefreshTask == nil else { return }
        viewModel.isQuotaRefreshing = true
        quotaRefreshTask = Task { [weak self] in
            guard let self else { return }
            defer {
                viewModel.isQuotaRefreshing = false
                quotaRefreshTask = nil
            }
            do {
                guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") else {
                    throw CodexLocalError.unavailable
                }
                let candidates = ["Contents/Resources/codex-cli/bin/codex", "Contents/Resources/codex"]
                guard let executable = candidates.map({ app.appendingPathComponent($0) }).first(where: {
                    FileManager.default.isExecutableFile(atPath: $0.path)
                }) else { throw CodexLocalError.unavailable }
                let response = try await SubscriptionQuotaReader.read(executable: executable)
                guard !Task.isCancelled else { return }
                viewModel.subscriptionQuota = response
                viewModel.quotaRefreshedAt = Date()
                viewModel.quotaRefreshFailed = false
                let defaults = UserDefaults.standard
                let threshold = defaults.object(forKey: "quotaWarningPercent") as? Double ?? 80
                let alerts = quotaAlerts.update(response, threshold: threshold)
                if defaults.object(forKey: "quotaAlertsEnabled") as? Bool ?? true, !alerts.isEmpty {
                    let language = InterfaceLanguage(rawValue: defaults.string(forKey: "interfaceLanguage") ?? "") ?? .english
                    viewModel.quotaAlertText = alerts.map { alert in
                        switch alert.kind {
                        case .warning: return language.text("\(alert.limit): subscription usage reached the warning threshold.", "\(alert.limit)：订阅用量达到预警阈值。")
                        case .exhausted: return language.text("\(alert.limit): subscription quota exhausted.", "\(alert.limit)：订阅额度已用完。")
                        case .reset: return language.text("\(alert.limit): subscription quota available again.", "\(alert.limit)：订阅额度已恢复。")
                        }
                    }.joined(separator: "\n")
                    notificationManager.notifyUserInputRequested()
                }
            } catch {
                viewModel.quotaRefreshFailed = true
            }
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
                    panelCoordinator.refreshFocusedPositionIfNeeded()
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
                self?.panelCoordinator.reconcilePanels()
            }
        }

        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.panelCoordinator.reconcilePanels()
            }
        }
    }

    private func scheduleLaunchReposition() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            self?.panelCoordinator.reconcilePanels()
        }
    }
}
