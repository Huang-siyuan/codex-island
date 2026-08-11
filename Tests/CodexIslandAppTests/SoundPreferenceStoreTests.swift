import Foundation
import Testing
@testable import CodexIslandCore

@Test
func soundPreferenceStoreDefaultsToEnabled() {
    let suiteName = "SoundPreferenceStoreTests.default.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let store = SoundPreferenceStore(userDefaults: defaults)

    #expect(store.isSoundEnabled)
}

@Test
func soundPreferenceStorePersistsToggleState() {
    let suiteName = "SoundPreferenceStoreTests.toggle.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let store = SoundPreferenceStore(userDefaults: defaults)
    #expect(!store.toggleSoundEnabled())
    #expect(!store.isSoundEnabled)

    let reloadedStore = SoundPreferenceStore(userDefaults: defaults)
    #expect(!reloadedStore.isSoundEnabled)
}

@Test
func soundPreferenceStorePersistsCustomCompletionSoundURL() {
    let suiteName = "SoundPreferenceStoreTests.custom.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)

    let soundURL = URL(fileURLWithPath: "/tmp/codex-island-finished.wav")
    let store = SoundPreferenceStore(userDefaults: defaults)
    store.customCompletionSoundURL = soundURL

    let reloadedStore = SoundPreferenceStore(userDefaults: defaults)
    #expect(reloadedStore.customCompletionSoundURL == soundURL)
    #expect(reloadedStore.customCompletionSoundDisplayName == "codex-island-finished.wav")

    reloadedStore.clearCustomCompletionSound()
    #expect(reloadedStore.customCompletionSoundURL == nil)
    #expect(reloadedStore.customCompletionSoundDisplayName == nil)
}
