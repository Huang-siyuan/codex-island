import CodexIslandCore
import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

enum IslandExpandedTab: String, CaseIterable, Identifiable {
    case sessions
    case usage

    var id: String { rawValue }

    func title(language: InterfaceLanguage) -> String {
        switch self {
        case .sessions:
            return language.text("Sessions", "会话")
        case .usage:
            return language.text("Usage", "用量")
        }
    }

    var systemImage: String {
        switch self {
        case .sessions:
            return "message.fill"
        case .usage:
            return "chart.bar.fill"
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
    @Published var threadTitle: String = "Watching AI tools"
    @Published var statusText: String = "Starting"
    @Published var latestToolSummary: String?
    @Published var sourceLabel: String = "AI Tools"
    @Published var activeSessionCount: Int = 0
    @Published var sessionPreviews: [SessionPreview] = []
    @Published var setupMessage: String?
    @Published var isSoundEnabled: Bool
    @Published var customCompletionSoundName: String?
    @Published var selectedExpandedTab: IslandExpandedTab = .sessions
    @Published var usageMetric: UsageDashboardMetric = .tokens
    @Published var usageSnapshot: LocalUsageSnapshot?
    @Published var compactBarHeight: CGFloat = 32
    @Published var compactBarWidth: CGFloat = IslandStatusPresentation.preferredCompactWidth
    @Published var compactTopAttachmentOverlap: CGFloat = MenuBarGeometry.resolvedCompactTopAttachmentOverlap(
        visibleHeight: 32
    )
    var onUsageRequested: (() -> Void)?

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

    func selectExpandedTab(_ tab: IslandExpandedTab) {
        selectedExpandedTab = tab
        if tab == .usage {
            onUsageRequested?()
        }
    }

    func refreshUsageIfSelected() {
        guard selectedExpandedTab == .usage else {
            return
        }
        onUsageRequested?()
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

    func toggleSoundEnabled() {
        isSoundEnabled = soundPreferenceStore.toggleSoundEnabled()
    }

    func chooseCustomCompletionSound(language: InterfaceLanguage) {
        let panel = NSOpenPanel()
        panel.title = language.text("Choose Completion Sound", "选择完成提示音")
        panel.message = language.text(
            "Pick an audio file to play when an AI task finishes.",
            "选择 AI 任务完成时播放的音频文件。"
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

    @discardableResult
    func updateCompactBarLayout(_ layout: MenuBarGeometry.CompactBarLayout) -> Bool {
        let normalizedHeight = max(22, ceil(layout.height))
        let normalizedWidth = max(IslandStatusPresentation.preferredCompactWidth, ceil(layout.width))
        let normalizedTopAttachmentOverlap = max(0, ceil(layout.topAttachmentOverlap))

        let heightChanged = abs(compactBarHeight - normalizedHeight) > 0.5
        let widthChanged = abs(compactBarWidth - normalizedWidth) > 0.5
        let topAttachmentChanged = abs(compactTopAttachmentOverlap - normalizedTopAttachmentOverlap) > 0.5

        guard heightChanged || widthChanged || topAttachmentChanged else {
            return false
        }

        if heightChanged {
            compactBarHeight = normalizedHeight
        }
        if widthChanged {
            compactBarWidth = normalizedWidth
        }
        if topAttachmentChanged {
            compactTopAttachmentOverlap = normalizedTopAttachmentOverlap
        }
        return true
    }

}
