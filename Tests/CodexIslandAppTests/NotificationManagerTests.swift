import Foundation
import Testing
@testable import CodexIslandCore

@MainActor
@Test
func notificationManagerDoesNotPresentBannerByDefault() {
    let suiteName = "NotificationManagerTests.default.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let soundStore = SoundPreferenceStore(userDefaults: defaults)
    var bannerCount = 0
    var soundCount = 0
    let manager = NotificationManager(
        soundPreferenceStore: soundStore,
        bannerPresenter: { _, _ in bannerCount += 1 },
        soundPlayer: { soundCount += 1 }
    )

    manager.notifyCompletion(provider: .codex, threadID: "thread-1", threadTitle: "Fix auth flow")

    #expect(bannerCount == 0)
    #expect(soundCount == 1)
}

@MainActor
@Test
func notificationManagerCanPresentBannerWhenExplicitlyEnabled() {
    let suiteName = "NotificationManagerTests.enabled.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let soundStore = SoundPreferenceStore(userDefaults: defaults)
    var capturedTitle: String?
    var capturedBody: String?
    let manager = NotificationManager(
        bannerStyle: .systemBanner,
        soundPreferenceStore: soundStore,
        bannerPresenter: { title, body in
            capturedTitle = title
            capturedBody = body
        },
        soundPlayer: {}
    )

    manager.notifyCompletion(provider: .claudeCode, threadID: "thread-2", threadTitle: "Ship markdown previews")

    #expect(capturedTitle == "Claude Code task finished")
    #expect(capturedBody == "Ship markdown previews")
}
