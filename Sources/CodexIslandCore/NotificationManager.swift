import AppKit
import Foundation

public enum CompletionBannerStyle: Sendable, Equatable {
    case hidden
    case systemBanner
}

@MainActor
public final class NotificationManager {
    private let policy: NotificationPolicy
    private let bannerStyle: CompletionBannerStyle
    private let soundPreferenceStore: SoundPreferenceStore
    private let bannerPresenter: @MainActor (_ title: String, _ body: String) -> Void
    private let soundPlayer: @MainActor () -> Void

    public init(
        policy: NotificationPolicy = NotificationPolicy(),
        bannerStyle: CompletionBannerStyle = .hidden,
        soundPreferenceStore: SoundPreferenceStore = SoundPreferenceStore(),
        bannerPresenter: @escaping @MainActor (_ title: String, _ body: String) -> Void = NotificationManager.defaultBannerPresenter,
        soundPlayer: @escaping @MainActor () -> Void = NotificationManager.defaultSoundPlayer
    ) {
        self.policy = policy
        self.bannerStyle = bannerStyle
        self.soundPreferenceStore = soundPreferenceStore
        self.bannerPresenter = bannerPresenter
        self.soundPlayer = soundPlayer
    }

    public func requestAuthorization() async {
        // The app now keeps macOS completion banners disabled by default, so
        // there is nothing to request up front.
    }

    public func notifyCompletion(provider: ProviderKind, threadID: String, threadTitle: String) {
        guard policy.shouldNotify(provider: provider, threadID: threadID, eventKind: .responseCompleted) else {
            return
        }

        if bannerStyle == .systemBanner {
            bannerPresenter("\(provider.displayName) task finished", threadTitle)
        }
        if soundPreferenceStore.isSoundEnabled {
            soundPlayer()
        }
    }

    public static func defaultSoundPlayer() {
        NSSound(named: .init("Glass"))?.play()
    }

    public static func defaultBannerPresenter(title: String, body: String) {
        let script = """
        display notification "\(escaped(body))" with title "\(escaped(title))"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
