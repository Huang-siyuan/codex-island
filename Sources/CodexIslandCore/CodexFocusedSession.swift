import AppKit
import ApplicationServices
import Foundation

public struct CodexFocusedWindow: Equatable, Sendable {
    public let title: String?
    public let document: String?
    public let windowID: String?

    public init(title: String?, document: String?, windowID: String? = nil) {
        self.title = title
        self.document = document
        self.windowID = windowID
    }
}

public struct FocusSessionTitle: Decodable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public enum SmartSilencePolicy {
    public static func shouldSilence(provider: ProviderKind, threadID: String, focused: CodexFocusedWindow?, titles: [FocusSessionTitle]) -> Bool {
        guard provider == .codex, let focused else { return false }
        if let document = focused.document, !document.isEmpty,
           let url = URL(string: document), url.scheme == "codex", url.host == "threads" {
            return url.pathComponents.filter { $0 != "/" }.first == threadID
        }
        guard let title = focused.title, !title.isEmpty else { return false }
        // Window titles can be duplicated or renamed. Suppress only an exact, unique current title.
        let matching = titles.filter { $0.title == title }
        return matching.count == 1 && matching[0].id == threadID
    }
}

@MainActor
public enum CodexFocusedWindowReader {
    public static var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    public static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public static func read() -> CodexFocusedWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == "com.openai.codex",
              AXIsProcessTrusted() else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.15)
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &result) == .success,
              let result, CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        let window = unsafeDowncast(result, to: AXUIElement.self)
        func text(_ attribute: String) -> String? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, attribute as CFString, &value) == .success else { return nil }
            return value as? String
        }
        return CodexFocusedWindow(title: text(kAXTitleAttribute), document: text(kAXDocumentAttribute), windowID: text(kAXIdentifierAttribute))
    }
}

/// Reuses Codex's authoritative title overrides; background work never reads Accessibility on the main loop.
public actor CodexFocusTitleIndex {
    private let environment: AppEnvironment
    private let indexReader = SessionIndexReader()
    private var version: DataSourceVersion?
    private var cached: [FocusSessionTitle] = []

    public init(environment: AppEnvironment = .default) { self.environment = environment }

    public func titles() -> [FocusSessionTitle] {
        let version = DataSourceVersion.capture(files: [environment.stateStoreURL,
            URL(fileURLWithPath: environment.stateStoreURL.path + "-wal"), environment.sessionIndexURL])
        if version == self.version { return cached }
        do {
            let rows: [FocusSessionTitle] = try SQLiteShell().query(databaseURL: environment.stateStoreURL,
                query: "select id, title from threads where archived = 0;")
            let overrides = try indexReader.readTitleOverrides(from: environment.sessionIndexURL, threadIDs: Set(rows.map(\.id)))
            cached = rows.map { FocusSessionTitle(id: $0.id, title: overrides[$0.id] ?? $0.title) }
            self.version = version
            return cached
        } catch {
            // A failed title read must never suppress an unrelated session notification.
            return []
        }
    }
}
