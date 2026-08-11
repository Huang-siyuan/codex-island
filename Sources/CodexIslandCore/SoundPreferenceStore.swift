import Foundation

public final class SoundPreferenceStore {
    private let userDefaults: UserDefaults
    private let key: String
    private let customCompletionSoundKey: String

    public init(
        userDefaults: UserDefaults = .standard,
        key: String = "isCompletionSoundEnabled",
        customCompletionSoundKey: String = "customCompletionSoundPath"
    ) {
        self.userDefaults = userDefaults
        self.key = key
        self.customCompletionSoundKey = customCompletionSoundKey
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

    public var customCompletionSoundURL: URL? {
        get {
            guard let path = userDefaults.string(forKey: customCompletionSoundKey), !path.isEmpty else {
                return nil
            }
            return URL(fileURLWithPath: path)
        }
        set {
            if let newValue {
                userDefaults.set(newValue.path, forKey: customCompletionSoundKey)
            } else {
                userDefaults.removeObject(forKey: customCompletionSoundKey)
            }
        }
    }

    public var customCompletionSoundDisplayName: String? {
        customCompletionSoundURL?.lastPathComponent
    }

    public func clearCustomCompletionSound() {
        customCompletionSoundURL = nil
    }
}
