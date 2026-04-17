import CodexIslandCore
import CoreGraphics
import Foundation

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
    }

    func apply(snapshot: IslandSnapshot) {
        threadTitle = snapshot.threadTitle
        statusText = snapshot.statusText
        latestToolSummary = snapshot.latestToolSummary
        sourceLabel = snapshot.sourceLabel
        activeSessionCount = snapshot.activeSessionCount
        sessionPreviews = snapshot.sessionPreviews
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
