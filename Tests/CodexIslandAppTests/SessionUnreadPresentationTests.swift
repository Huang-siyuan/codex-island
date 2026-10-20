@testable import CodexIslandApp
import CodexIslandCore
import Foundation
import Testing

@MainActor
struct SessionUnreadPresentationTests {
    @Test
    func cardsTrackUnreadIdentityIndependentlyOfExecutionStateAndProvider() {
        let suite = "SessionUnreadPresentationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = IslandViewModel(
            focusRouter: FocusRouter(),
            soundPreferenceStore: SoundPreferenceStore(userDefaults: defaults)
        )
        model.unreadCodexThreadIDs = ["one"]
        for status in ["Running", "Completed", "Waiting for input"] {
            #expect(model.isUnread(preview(id: "one", status: status)))
        }
        #expect(!model.isUnread(preview(id: "two")))
        #expect(!model.isUnread(preview(id: "one", provider: .claudeCode)))
        #expect(!model.isUnread(preview(id: "one", provider: .codeBuddy)))
        // The count can stay unchanged while the card needing attention changes.
        model.unreadCodexThreadIDs = ["two"]
        #expect(model.unreadCodexThreadCount == 1)
        #expect(!model.isUnread(preview(id: "one")))
        #expect(model.isUnread(preview(id: "two")))
        model.unreadCodexThreadIDs = []
        #expect(!model.isUnread(preview(id: "two")))
        #expect(model.unreadCodexThreadCount == 0)
        model.unreadCodexThreadIDs = nil
        #expect(!model.isUnread(preview(id: "two")))
        #expect(model.unreadCodexThreadCount == nil)
    }

    private func preview(
        id: String,
        provider: ProviderKind = .codex,
        status: String = "Completed"
    ) -> SessionPreview {
        SessionPreview(
            provider: provider, threadID: id, title: "Session",
            statusText: status, sourceLabel: "Desktop",
            userPreview: nil, assistantPreview: nil, latestToolSummary: nil,
            updatedAt: Date(), isPrimary: false
        )
    }
}
