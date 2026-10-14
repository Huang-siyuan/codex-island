import AppKit
import CodexIslandCore
import SwiftUI

struct IslandSettingsView: View {
    @ObservedObject var viewModel: IslandViewModel
    @ObservedObject var launchAtLoginStore: LaunchAtLoginStore
    @AppStorage("interfaceLanguage") private var interfaceLanguageRaw = InterfaceLanguage.english.rawValue
    @AppStorage("islandAppearance") private var islandAppearanceRaw = IslandAppearance.classic.rawValue

    private var language: InterfaceLanguage {
        InterfaceLanguage(rawValue: interfaceLanguageRaw) ?? .english
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language.text("Settings", "设置"))
                .font(.system(size: 14, weight: .semibold))

            HStack(alignment: .top, spacing: 12) {
                generalSettings
                soundSettings
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .onAppear {
            launchAtLoginStore.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLoginStore.refresh()
        }
    }

    private var generalSettings: some View {
        settingsSection(language.text("General", "通用")) {
            VStack(alignment: .leading, spacing: 5) {
                Toggle(language.text("Launch at login", "开机自启动"), isOn: Binding(
                    get: { launchAtLoginStore.isRequested },
                    set: { launchAtLoginStore.setEnabled($0) }
                ))
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("settings.launchAtLogin")

                Text(language.text("Open Codex Island when you log in to your Mac.", "登录 Mac 后自动启动 Codex Island。"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }

            if launchAtLoginStore.status == .requiresApproval {
                Text(language.text(
                    "Waiting for approval in System Settings; automatic launch is not active yet.",
                    "等待系统设置批准，自动启动尚未生效。"
                ))
                .foregroundStyle(.white.opacity(0.7))
                Button(language.text("Open Login Items Settings", "打开登录项设置")) {
                    launchAtLoginStore.openSystemSettings()
                }
            }

            if let message = launchAtLoginStore.errorMessage {
                Text(language.text("Could not update launch at login: ", "无法更新自启动设置：") + message)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            Divider().overlay(.white.opacity(0.08))

            VStack(alignment: .leading, spacing: 6) {
                Text(language.text("Language", "语言"))
                    .foregroundStyle(.white.opacity(0.7))
                Picker(language.text("Language", "语言"), selection: $interfaceLanguageRaw) {
                    Text("English").tag(InterfaceLanguage.english.rawValue)
                    Text("简体中文").tag(InterfaceLanguage.simplifiedChinese.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(language.text("Appearance", "外观"))
                    .foregroundStyle(.white.opacity(0.7))
                Picker(language.text("Appearance", "外观"), selection: $islandAppearanceRaw) {
                    ForEach(IslandAppearance.allCases) { appearance in
                        Text(appearance.title(language: language)).tag(appearance.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    private var soundSettings: some View {
        settingsSection(language.text("Completion sound", "完成提示音")) {
            Toggle(language.text("Play completion sound", "播放完成提示音"), isOn: Binding(
                get: { viewModel.isSoundEnabled },
                set: { viewModel.setSoundEnabled($0) }
            ))
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("settings.completionSound")

            Divider().overlay(.white.opacity(0.08))

            VStack(alignment: .leading, spacing: 6) {
                Text(language.text("Sound", "音效"))
                    .foregroundStyle(.white.opacity(0.7))
                Text(viewModel.customCompletionSoundName ?? language.text("Built-in chime", "内置双音提示音"))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .help(viewModel.customCompletionSoundName ?? language.text("Built-in chime", "内置双音提示音"))
            }

            HStack {
                Button(language.text("Choose audio…", "选择音频…")) {
                    viewModel.chooseCustomCompletionSound(language: language)
                }
                if viewModel.customCompletionSoundName != nil {
                    Button(language.text("Use built-in sound", "恢复内置提示音")) {
                        viewModel.clearCustomCompletionSound()
                    }
                }
            }
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            content()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        }
    }
}
