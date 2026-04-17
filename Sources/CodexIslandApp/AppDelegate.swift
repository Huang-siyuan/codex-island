import AppKit
import CodexIslandCore
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let focusRouter = FocusRouter()
    private let firstLaunchSetup = FirstLaunchSetup()
    private let pollingEngine = PollingEngine()
    private let screenLocator = ActiveScreenLocator()
    private let soundPreferenceStore = SoundPreferenceStore()

    private lazy var notificationManager = NotificationManager(soundPreferenceStore: soundPreferenceStore)
    private lazy var viewModel = IslandViewModel(
        focusRouter: focusRouter,
        soundPreferenceStore: soundPreferenceStore
    )
    private var panelController: IslandPanelController?
    private var pollingTask: Task<Void, Never>?
    private var workspaceActivationObserver: NSObjectProtocol?
    private var screenParametersObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        screenLocator.noteActivatedApplication(NSWorkspace.shared.frontmostApplication)
        panelController = IslandPanelController(viewModel: viewModel, screenLocator: screenLocator)
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
            panelController?.refreshPosition()

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

    private func installPositionObservers() {
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
