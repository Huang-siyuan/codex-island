import AppKit
import Foundation

@MainActor
public final class NotificationManager {
    private let policy: NotificationPolicy
    private let soundPreferenceStore: SoundPreferenceStore

    public init(
        policy: NotificationPolicy = NotificationPolicy(),
        soundPreferenceStore: SoundPreferenceStore = SoundPreferenceStore()
    ) {
        self.policy = policy
        self.soundPreferenceStore = soundPreferenceStore
    }

    public func requestAuthorization() async {
        // `display notification` does not need a separate app-bundle-backed
        // notification center, so there is nothing to request here.
    }

    public func notifyCompletion(threadID: String, threadTitle: String) {
        guard policy.shouldNotify(threadID: threadID, eventKind: .responseCompleted) else {
            return
        }

        let script = """
        display notification "\(escaped(threadTitle))" with title "Codex task finished"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        if soundPreferenceStore.isSoundEnabled {
            NSSound(named: .init("Glass"))?.play()
        }
    }

    private func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
