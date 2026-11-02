@testable import CodexIslandApp
@testable import CodexIslandCore
import AppKit
import SwiftUI
import Testing

@MainActor
@Test(.enabled(if: ProcessInfo.processInfo.environment["CODEX_ISLAND_RENDER_UI"] == "1"))
func renderSubscriptionQuestionAndSettingsInBothLanguagesAndAppearances() throws {
    let directory = URL(fileURLWithPath: "/tmp/codex-island-ui")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let defaults = UserDefaults.standard
    let originalLanguage = defaults.object(forKey: "interfaceLanguage")
    let originalAppearance = defaults.object(forKey: "islandAppearance")
    defer {
        defaults.set(originalLanguage, forKey: "interfaceLanguage")
        defaults.set(originalAppearance, forKey: "islandAppearance")
    }
    let viewModel = IslandViewModel(focusRouter: FocusRouter(), soundPreferenceStore: SoundPreferenceStore())
    viewModel.subscriptionQuota = try JSONDecoder().decode(SubscriptionQuotaResponse.self, from: Data(#"{"rateLimits":{"limitId":"codex","planType":"pro","primary":{"usedPercent":83,"windowDurationMins":300,"resetsAt":1793885488},"secondary":{"usedPercent":53,"windowDurationMins":10080,"resetsAt":1793885488}}}"#.utf8))
    viewModel.quotaRefreshedAt = Date()
    let questions = try JSONDecoder().decode([CodexQuestion].self, from: Data(#"[{"id":"scope","header":"Scope / 范围","question":"Which implementation should we use? 请选择实现方式。","isOther":true,"options":[{"label":"Recommended / 推荐方案","description":"Keep existing behavior and add the requested controls. 保留现有行为并添加所需控件。"},{"label":"Custom / 自定义","description":"Describe your preferred behavior. 描述你希望的行为。"}]}]"#.utf8))
    let request = CodexQuestionRequest(threadID: "preview", requestID: .number(1), ownerID: "preview", questions: questions)
    viewModel.applyQuestions([request])
    viewModel.activeQuestionID = request.id
    for language in InterfaceLanguage.allCases {
        defaults.set(language.rawValue, forKey: "interfaceLanguage")
        for appearance in IslandAppearance.allCases {
            defaults.set(appearance.rawValue, forKey: "islandAppearance")
            let pages: [(String, AnyView)] = [
                ("quota-question", AnyView(VStack(spacing: 12) {
                    SubscriptionQuotaView(viewModel: viewModel, language: language)
                    CodexQuestionView(viewModel: viewModel, request: request, language: language)
                })),
                ("settings", AnyView(IslandSettingsView(viewModel: viewModel, launchAtLoginStore: viewModel.launchAtLoginStore, displayPreferences: IslandDisplayPreferences())))
            ]
            for (page, content) in pages {
                let host = NSHostingView(rootView: content.padding(16).frame(width: 620)
                    .background(IslandOverlayBackground(appearance: appearance))
                    .foregroundStyle(IslandPalette.title).environment(\.colorScheme, .dark).environment(\.locale, language.locale))
                let size = host.fittingSize
                #expect(size.height > 100 && size.height < 1400)
                host.frame = NSRect(origin: .zero, size: size)
                let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("\(page)-\(language.rawValue)-\(appearance.rawValue).png"))
                window.close()
            }
        }
    }
}
