import SwiftUI

@main
struct CodexIslandApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            VStack(alignment: .leading, spacing: 12) {
                Text("Codex Island")
                    .font(.headline)
                Text("The floating island is already running near the top of the screen.")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 340, height: 120)
            .padding()
        }
    }
}
