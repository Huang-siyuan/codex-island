import CodexIslandCore
import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

enum IslandExpandedTab: String, CaseIterable, Identifiable {
    case sessions
    case usage
    case settings

    var id: String { rawValue }

    func title(language: InterfaceLanguage) -> String {
        switch self {
        case .sessions:
            return language.text("Sessions", "会话")
        case .usage:
            return language.text("Usage", "用量")
        case .settings:
            return language.text("Settings", "设置")
        }
    }

    var systemImage: String {
        switch self {
        case .sessions:
            return "message.fill"
        case .usage:
            return "chart.bar.fill"
        case .settings:
            return "gearshape.fill"
        }
    }
}

enum UsageDashboardMetric: String, CaseIterable, Identifiable {
    case tokens
    case time

    var id: String { rawValue }

    func title(language: InterfaceLanguage) -> String {
        switch self {
        case .tokens:
            return language.text("Tokens", "Token")
        case .time:
            return language.text("Time", "时间")
        }
    }
}

@MainActor
final class IslandViewModel: ObservableObject {
    let launchAtLoginStore = LaunchAtLoginStore()
    @Published var threadTitle: String = "Watching AI tools"
    @Published var statusText: String = "Starting"
    @Published var latestToolSummary: String?
    @Published var sourceLabel: String = "AI Tools"
    @Published var activeSessionCount: Int = 0
    @Published var unreadCodexThreadCount: Int?
    @Published var sessionPreviews: [SessionPreview] = []
    @Published var setupMessage: String?
    @Published var isSoundEnabled: Bool
    @Published var customCompletionSoundName: String?
    @Published var usageSnapshot: LocalUsageSnapshot?
    @Published var isUsageRefreshing = false
    var onUsageRequested: (() -> Void)?
    var onUsageRefreshRequested: (() -> Void)?

    private let focusRouter: FocusRouter
    private let soundPreferenceStore: SoundPreferenceStore

    init(focusRouter: FocusRouter, soundPreferenceStore: SoundPreferenceStore) {
        self.focusRouter = focusRouter
        self.soundPreferenceStore = soundPreferenceStore
        self.isSoundEnabled = soundPreferenceStore.isSoundEnabled
        self.customCompletionSoundName = soundPreferenceStore.customCompletionSoundDisplayName
    }

    func apply(snapshot: IslandSnapshot) {
        if threadTitle != snapshot.threadTitle {
            threadTitle = snapshot.threadTitle
        }
        if statusText != snapshot.statusText {
            statusText = snapshot.statusText
        }
        if latestToolSummary != snapshot.latestToolSummary {
            latestToolSummary = snapshot.latestToolSummary
        }
        if sourceLabel != snapshot.sourceLabel {
            sourceLabel = snapshot.sourceLabel
        }
        if activeSessionCount != snapshot.activeSessionCount {
            activeSessionCount = snapshot.activeSessionCount
        }
        if sessionPreviews != snapshot.sessionPreviews {
            sessionPreviews = snapshot.sessionPreviews
        }
    }

    func requestUsageRefresh() {
        guard !isUsageRefreshing else {
            return
        }
        onUsageRefreshRequested?()
    }

    func applyUsageSnapshot(_ snapshot: LocalUsageSnapshot) {
        if usageSnapshot != snapshot {
            usageSnapshot = snapshot
        }
    }

    func showSetupResult(_ result: SetupResult?) {
        guard let result else {
            setupMessage = nil
            return
        }
        if result.didPerform {
            setupMessage = result.shellUpdated
                ? "CLI helper installed and zsh updated"
                : "CLI helper installed"
        }
    }

    func openSession(_ preview: SessionPreview) {
        _ = focusRouter.activateSession(preview.navigationTarget)
    }

    func setSoundEnabled(_ enabled: Bool) {
        soundPreferenceStore.isSoundEnabled = enabled
        isSoundEnabled = soundPreferenceStore.isSoundEnabled
    }

    func previewCompletionSound() {
        // Manual preview remains available when automatic notification sounds are muted.
        NotificationManager.defaultSoundPlayer(customSoundURL: soundPreferenceStore.customCompletionSoundURL)
    }

    func chooseCustomCompletionSound(language: InterfaceLanguage) {
        let panel = NSOpenPanel()
        panel.title = language.text("Choose Notification Sound", "选择提示音")
        panel.message = language.text(
            "Pick an audio file for task completion and Codex input requests.",
            "选择任务完成或 Codex 等待输入时播放的音频文件。"
        )
        panel.prompt = language.text("Use Sound", "使用此音效")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.audio]

        guard panel.runModal() == .OK, let soundURL = panel.url else {
            return
        }

        soundPreferenceStore.customCompletionSoundURL = soundURL
        soundPreferenceStore.isSoundEnabled = true
        customCompletionSoundName = soundPreferenceStore.customCompletionSoundDisplayName
        isSoundEnabled = true
    }

    func clearCustomCompletionSound() {
        soundPreferenceStore.clearCustomCompletionSound()
        customCompletionSoundName = nil
    }
}
