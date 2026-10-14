import SwiftUI

// Both appearances share foreground and control semantics; only the shell material changes.
enum IslandPalette {
    static let title = Color.white.opacity(0.95)
    static let subtitle = Color.white.opacity(0.72)
    static let muted = Color.white.opacity(0.56)
    static let accent = Color(red: 0.28, green: 0.86, blue: 0.55)
    static let onAccent = Color(red: 0.04, green: 0.12, blue: 0.08)
    static let surface = Color.white.opacity(0.05)
    static let emphasizedSurface = Color.white.opacity(0.10)
    static let border = Color.white.opacity(0.09)
    static let separator = Color.white.opacity(0.10)
    static let selectedSurface = accent.opacity(0.16)
    static let selectedBorder = accent.opacity(0.42)
    static let hoverSurface = Color.white.opacity(0.10)
    static let pressedSurface = Color.white.opacity(0.16)
    static let tool = Color.orange
    static let running = Color.yellow
    static let completed = accent
    static let passive = Color.gray
    static let error = Color.red

    static let classicBackground = LinearGradient(
        colors: [Color.black.opacity(0.96), Color(red: 0.10, green: 0.11, blue: 0.14)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let glassTint = LinearGradient(
        colors: [
            Color(red: 0.28, green: 0.10, blue: 0.44).opacity(0.22),
            Color(red: 0.08, green: 0.17, blue: 0.38).opacity(0.16),
            Color(red: 0.02, green: 0.34, blue: 0.72).opacity(0.20),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
    static let glassHighlight = LinearGradient(
        colors: [Color.white.opacity(0.13), .clear, Color.black.opacity(0.08)],
        startPoint: .top,
        endPoint: .bottom
    )
    static let glassBorder = LinearGradient(
        colors: [Color.white.opacity(0.52), Color.white.opacity(0.18), accent.opacity(0.28)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

enum IslandTypography {
    static let heading = Font.system(size: 14, weight: .semibold)
    static let section = Font.system(size: 12, weight: .semibold)
    static let body = Font.system(size: 12)
    static let control = Font.system(size: 11, weight: .semibold)
    static let caption = Font.system(size: 11, weight: .medium)
}

enum IslandLayout {
    static let sectionSpacing: CGFloat = 12
    static let cardPadding: CGFloat = 14
    static let cardRadius: CGFloat = 16
    static let shellRadius: CGFloat = 28
    static let controlHeight: CGFloat = 28
}

struct IslandSurface: ViewModifier {
    var emphasized = false
    var highlighted = false

    func body(content: Content) -> some View {
        content
            .background(
                emphasized ? IslandPalette.emphasizedSurface : IslandPalette.surface,
                in: RoundedRectangle(cornerRadius: IslandLayout.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: IslandLayout.cardRadius, style: .continuous)
                    .strokeBorder(highlighted ? IslandPalette.selectedBorder : IslandPalette.border, lineWidth: 1)
            }
    }
}

struct IslandSeparator: View {
    var body: some View {
        Rectangle()
            .fill(IslandPalette.separator)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

struct IslandOverlayBackground: View {
    let appearance: IslandAppearance

    var body: some View {
        switch appearance {
        case .classic:
            IslandPalette.classicBackground
        case .macOSGlass:
            ZStack {
                MacOSVisualEffectView(material: .hudWindow)
                IslandPalette.glassTint
                IslandPalette.glassHighlight
            }
        }
    }
}
