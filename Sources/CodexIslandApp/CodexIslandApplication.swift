import CodexIslandCore
import SwiftUI

@main
struct CodexIslandApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var launchAtLoginStore = LaunchAtLoginStore()

    var body: some Scene {
        Settings {
            IslandSettingsView(
                viewModel: appDelegate.viewModel,
                launchAtLoginStore: launchAtLoginStore
            )
        }
    }
}
