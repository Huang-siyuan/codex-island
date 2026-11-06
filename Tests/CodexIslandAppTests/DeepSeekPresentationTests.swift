import AppKit
import SwiftUI
import Testing

@testable import CodexIslandApp
@testable import CodexIslandCore

@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["ISLAND_RENDER_DEEPSEEK"] == "1"))
func deepSeekPresentationInBothLanguagesAndAppearances() throws {
    _ = NSApplication.shared
    let suite = "DeepSeekPresentation.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = IslandViewModel(
        focusRouter: FocusRouter(), soundPreferenceStore: SoundPreferenceStore(userDefaults: defaults))
    let request = CodexQuestionRequest(
        provider: .deepSeek, threadID: "fixture", requestID: .string("question"), ownerID: "fixture",
        questions: [
            .init(
                id: "q", header: "选择验证范围 / Select validation",
                question: "哪些功能需要验证？Which features should be checked?", isOther: true, isSecret: false,
                options: [
                    .init(label: "会话状态 / Session status", description: "运行、工具调用与完成提示"),
                    .init(label: "问题回答 / Questions", description: "支持多选和补充说明"),
                ], multiSelect: true)
        ])
    model.applyQuestions([request])
    model.activeQuestionID = request.id
    model.setAnswer(
        #"{"selected":["会话状态 / Session status"],"custom":"补充说明 / Additional context"}"#,
        questionID: "q", requestID: request.id)
    let balance = try JSONDecoder().decode(
        DeepSeekBalance.self,
        from: Data(
            #"{"status":"ready","value":[{"currency":"CNY","balance":"12.34"}],"bonusWallets":[]}"#.utf8))
    let usage = DeepSeekUsageSummary(
        id: "s", title: "兼容测试 / Compatibility test",
        tokens: .init(
            uncachedInputTokens: 10000, outputTokens: 3000, cacheReadTokens: 50000, cacheWriteTokens: 0),
        contextTokens: 63000, contextWindow: 128000)
    for language in InterfaceLanguage.allCases {
        for appearance in IslandAppearance.allCases {
            let view = VStack(spacing: IslandLayout.sectionSpacing) {
                DeepSeekUsageView(
                    usage: [usage], connected: true, account: .balance(balance), language: language)
                CodexQuestionView(viewModel: model, request: request, language: language)
            }
            .padding(18)
            .frame(width: 420)
            .foregroundStyle(IslandPalette.title)
            .background(IslandOverlayBackground(appearance: appearance))
            .environment(\.colorScheme, .dark)
            .environment(\.locale, language.locale)
            let hosting = NSHostingView(rootView: view)
            hosting.setFrameSize(hosting.fittingSize)
            hosting.layoutSubtreeIfNeeded()
            #expect(hosting.frame.height > 300)
            #expect(hosting.frame.height < 850)
            let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(
                to: URL(fileURLWithPath: "/tmp/deepseek-\(language.rawValue)-\(appearance.rawValue).png"))
        }
    }
}
