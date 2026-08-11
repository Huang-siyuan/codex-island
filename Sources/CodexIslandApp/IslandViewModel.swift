import CodexIslandCore
import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

enum IslandExpandedTab: String, CaseIterable, Identifiable {
    case sessions
    case usage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sessions:
            return "Sessions"
        case .usage:
            return "Usage"
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

    var title: String {
        switch self {
        case .tokens:
            return "Tokens"
        case .time:
            return "Time"
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

    private let focusRouter: FocusRouter
    private let soundPreferenceStore: SoundPreferenceStore

    init(focusRouter: FocusRouter, soundPreferenceStore: SoundPreferenceStore) {
        self.focusRouter = focusRouter
        self.soundPreferenceStore = soundPreferenceStore
        self.isSoundEnabled = soundPreferenceStore.isSoundEnabled
        self.customCompletionSoundName = soundPreferenceStore.customCompletionSoundDisplayName
    }

    func apply(snapshot: IslandSnapshot, usageSnapshot: LocalUsageSnapshot?) {
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
        if self.usageSnapshot != usageSnapshot {
            self.usageSnapshot = usageSnapshot
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

    func chooseCustomCompletionSound() {
        let panel = NSOpenPanel()
        panel.title = "Choose Completion Sound"
        panel.message = "Pick an audio file to play when an AI task finishes."
        panel.prompt = "Use Sound"
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
