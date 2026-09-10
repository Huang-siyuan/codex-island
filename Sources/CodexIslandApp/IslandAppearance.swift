import CodexIslandCore
import Foundation

enum IslandAppearance: String, CaseIterable, Identifiable {
    case classic
    case macOSGlass

    var id: String { rawValue }

    func title(language: InterfaceLanguage) -> String {
        switch self {
        case .classic:
            return language.text("Classic Dark", "经典深色")
        case .macOSGlass:
            return language.text("macOS Glass", "macOS 玻璃")
        }
    }
}
