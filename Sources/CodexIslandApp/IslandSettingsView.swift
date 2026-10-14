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
        VStack(alignment: .leading, spacing: IslandLayout.sectionSpacing) {
            Text(language.text("Settings", "设置"))
                .font(IslandTypography.heading)

            HStack(alignment: .top, spacing: IslandLayout.sectionSpacing) {
                generalSettings
                soundSettings
            }
        }
        .font(IslandTypography.body)
        .foregroundStyle(IslandPalette.title)
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
                .toggleStyle(IslandCheckboxStyle())
                .accessibilityIdentifier("settings.launchAtLogin")

                Text(language.text("Open Codex Island when you log in to your Mac.", "登录 Mac 后自动启动 Codex Island。"))
                    .font(IslandTypography.caption)
                    .foregroundStyle(IslandPalette.muted)
            }

            if launchAtLoginStore.status == .requiresApproval {
                Text(language.text(
                    "Waiting for approval in System Settings; automatic launch is not active yet.",
                    "等待系统设置批准，自动启动尚未生效。"
                ))
                .foregroundStyle(IslandPalette.subtitle)
                Button(language.text("Open Login Items Settings", "打开登录项设置")) {
                    launchAtLoginStore.openSystemSettings()
                }
            }

            if let message = launchAtLoginStore.errorMessage {
                Text(language.text("Could not update launch at login: ", "无法更新自启动设置：") + message)
                    .font(IslandTypography.caption)
                    .foregroundStyle(IslandPalette.error)
                    .textSelection(.enabled)
            }

            IslandSeparator()

            VStack(alignment: .leading, spacing: 6) {
                Text(language.text("Language", "语言"))
                    .foregroundStyle(IslandPalette.subtitle)
                IslandChoiceGroup(
                    title: language.text("Language", "语言"),
                    options: InterfaceLanguage.allCases.map(\.rawValue),
                    selection: $interfaceLanguageRaw,
                    fillsWidth: true
                ) { value in
                    Text(value == InterfaceLanguage.english.rawValue ? "English" : "简体中文")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(language.text("Appearance", "外观"))
                    .foregroundStyle(IslandPalette.subtitle)
                IslandChoiceGroup(
                    title: language.text("Appearance", "外观"),
                    options: IslandAppearance.allCases.map(\.rawValue),
                    selection: $islandAppearanceRaw,
                    fillsWidth: true
                ) { value in
                    Text((IslandAppearance(rawValue: value) ?? .classic).title(language: language))
                }
            }
        }
    }

    private var soundSettings: some View {
        settingsSection(language.text("Completion sound", "完成提示音")) {
            Toggle(language.text("Play completion sound", "播放完成提示音"), isOn: Binding(
                get: { viewModel.isSoundEnabled },
                set: { viewModel.setSoundEnabled($0) }
            ))
            .toggleStyle(IslandCheckboxStyle())
            .accessibilityIdentifier("settings.completionSound")

            IslandSeparator()

            VStack(alignment: .leading, spacing: 6) {
                Text(language.text("Sound", "音效"))
                    .foregroundStyle(IslandPalette.subtitle)
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
        VStack(alignment: .leading, spacing: IslandLayout.sectionSpacing) {
            Text(title)
                .font(IslandTypography.section)
            content()
        }
        .buttonStyle(IslandButtonStyle())
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(IslandLayout.cardPadding)
        .modifier(IslandSurface())
    }
}
