import Foundation

public enum InterfaceLanguage: String, CaseIterable, Sendable {
    case english
    case simplifiedChinese

    public var toggleTitle: String {
        switch self {
        case .english:
            return "中"
        case .simplifiedChinese:
            return "EN"
        }
    }

    public var locale: Locale {
        switch self {
        case .english:
            return Locale(identifier: "en_US")
        case .simplifiedChinese:
            return Locale(identifier: "zh_Hans_CN")
        }
    }

    public func text(_ english: String, _ simplifiedChinese: String) -> String {
        switch self {
        case .english:
            return english
        case .simplifiedChinese:
            return simplifiedChinese
        }
    }

    public func statusText(for statusText: String) -> String {
        switch statusText {
        case "Starting":
            return text("Starting", "启动中")
        case "Running":
            return text("Running", "运行中")
        case "Tool active":
            return text("Tool active", "工具执行中")
        case "Done":
            return text("Done", "已完成")
        case "Watching", "Watching Codex":
            return text(statusText, statusText == "Watching" ? "监看中" : "监看 Codex")
        default:
            return statusText
        }
    }

    public func compactStatusText(for statusText: String) -> String {
        switch statusText {
        case "Tool active":
            return text("Tool active", "工具中")
        case "Running":
            return text("Running", "运行中")
        default:
            return text("Watching", "监看中")
        }
    }
}
