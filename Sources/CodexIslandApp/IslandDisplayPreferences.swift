import CodexIslandCore
import Combine
import Foundation

enum IslandDisplayMode: String, CaseIterable {
    case followFocus
    case everyScreen

    func title(language: InterfaceLanguage) -> String {
        switch self {
        case .followFocus:
            return language.text("Follow focus", "跟随聚焦")
        case .everyScreen:
            return language.text("One Island per screen", "每个屏幕一个刘海")
        }
    }
}

@MainActor
final class IslandDisplayPreferences: ObservableObject {
    static let defaultsKey = "islandDisplayMode"
    private let defaults: UserDefaults

    @Published var mode: IslandDisplayMode {
        didSet { defaults.set(mode.rawValue, forKey: Self.defaultsKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: Self.defaultsKey)
            .flatMap(IslandDisplayMode.init(rawValue:)) ?? .followFocus
    }
}
