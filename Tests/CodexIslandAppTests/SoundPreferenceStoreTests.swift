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
