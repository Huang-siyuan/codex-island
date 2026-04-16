import Foundation

public final class SoundPreferenceStore {
    private let userDefaults: UserDefaults
    private let key: String

    public init(
        userDefaults: UserDefaults = .standard,
        key: String = "isCompletionSoundEnabled"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    public var isSoundEnabled: Bool {
        get {
            guard userDefaults.object(forKey: key) != nil else {
                return true
            }
            return userDefaults.bool(forKey: key)
        }
        set {
            userDefaults.set(newValue, forKey: key)
        }
    }

    @discardableResult
    public func toggleSoundEnabled() -> Bool {
        let nextValue = !isSoundEnabled
        isSoundEnabled = nextValue
        return nextValue
    }
}
