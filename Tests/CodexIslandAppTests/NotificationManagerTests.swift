import AppKit
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
        soundPlayer: { _ in soundCount += 1 }
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
        soundPlayer: { _ in }
    )

    manager.notifyCompletion(provider: .claudeCode, threadID: "thread-2", threadTitle: "Ship markdown previews")

    #expect(capturedTitle == "Claude Code task finished")
    #expect(capturedBody == "Ship markdown previews")
}

@MainActor
@Test
func notificationManagerPassesCustomCompletionSoundToSoundPlayer() {
    let suiteName = "NotificationManagerTests.customSound.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let soundURL = URL(fileURLWithPath: "/tmp/codex-island-finished.m4a")
    let soundStore = SoundPreferenceStore(userDefaults: defaults)
    soundStore.customCompletionSoundURL = soundURL
    var capturedSoundURL: URL?
    let manager = NotificationManager(
        soundPreferenceStore: soundStore,
        bannerPresenter: { _, _ in },
        soundPlayer: { customSoundURL in
            capturedSoundURL = customSoundURL
        }
    )

    manager.notifyCompletion(provider: .codex, threadID: "thread-3", threadTitle: "Finish task")

    #expect(capturedSoundURL == soundURL)
}

@MainActor
@Test
func completionSoundDefaultsToBundledChime() throws {
    let sound = try #require(NotificationManager.completionSound(customSoundURL: nil))

    #expect(abs(sound.duration - 0.8) < 0.01)
}

@MainActor
@Test
func completionSoundFallsBackWhenCustomFileIsMissingOrInvalid() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let customURL = directory.appendingPathComponent("custom.wav")

    let missingFallback = try #require(NotificationManager.completionSound(customSoundURL: customURL))
    #expect(abs(missingFallback.duration - 0.8) < 0.01)

    try Data("not an audio file".utf8).write(to: customURL)
    let invalidFallback = try #require(NotificationManager.completionSound(customSoundURL: customURL))
    #expect(abs(invalidFallback.duration - 0.8) < 0.01)
}

@MainActor
@Test
func completionSoundPrefersValidCustomAudio() throws {
    let customURL = URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff")
    let expected = try #require(NSSound(contentsOf: customURL, byReference: false))
    let actual = try #require(NotificationManager.completionSound(customSoundURL: customURL))

    #expect(actual.duration == expected.duration)
    #expect(abs(actual.duration - 0.8) > 0.01)
}

@MainActor
@Test
func notificationManagerRespectsMuteWithBuiltInSound() {
    let suiteName = "NotificationManagerTests.muted.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let soundStore = SoundPreferenceStore(userDefaults: defaults)
    soundStore.isSoundEnabled = false
    var soundCount = 0
    let manager = NotificationManager(
        soundPreferenceStore: soundStore,
        soundPlayer: { _ in soundCount += 1 }
    )

    manager.notifyCompletion(provider: .codex, threadID: "muted", threadTitle: "Finish task")

    #expect(soundCount == 0)
}

@MainActor
@Test
func notificationManagerUsesDefaultAfterClearingCustomSound() {
    let suiteName = "NotificationManagerTests.cleared.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let soundStore = SoundPreferenceStore(userDefaults: defaults)
    soundStore.customCompletionSoundURL = URL(fileURLWithPath: "/tmp/custom.wav")
    var soundCount = 0
    let manager = NotificationManager(
        soundPreferenceStore: soundStore,
        soundPlayer: { customURL in
            #expect(customURL == nil)
            soundCount += 1
        }
    )
    soundStore.clearCustomCompletionSound()

    manager.notifyCompletion(provider: .codex, threadID: "cleared", threadTitle: "Finish task")

    #expect(soundCount == 1)
}
