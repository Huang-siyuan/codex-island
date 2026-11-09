import CodexIslandCore
import SwiftUI

struct IslandProviderBadge: View {
    let provider: ProviderKind

    private var label: String {
        switch provider {
        case .codex: return "codex"
        case .deepSeek: return "DSH"
        default: return provider.displayName
        }
    }

    private var tint: Color {
        switch provider {
        case .codex: return IslandPalette.providerCodex
        case .deepSeek: return IslandPalette.providerDSH
        default: return IslandPalette.subtitle
        }
    }

    var body: some View {
        Text(label)
            .font(IslandTypography.control)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
            .fixedSize()
            .accessibilityLabel(provider.displayName)
    }
}

struct IslandUnreadBadge: View {
    let language: InterfaceLanguage

    var body: some View {
        Text(language.text("Unread", "未读"))
            .font(IslandTypography.control)
            .foregroundStyle(IslandPalette.unread)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(IslandPalette.unreadSurface, in: Capsule())
            .fixedSize()
            .accessibilityLabel(language.text("Unread conversation", "未读会话"))
    }
}

struct IslandButtonStyle: ButtonStyle {
    var isSelected = false
    var isMultiline = false

    func makeBody(configuration: Configuration) -> some View {
        IslandButtonBody(configuration: configuration, isSelected: isSelected, isMultiline: isMultiline)
    }
}

private struct IslandButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    let isMultiline: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    private var fill: Color {
        if configuration.isPressed {
            return IslandPalette.pressedSurface
        }
        if isSelected {
            return IslandPalette.selectedSurface
        }
        return isHovered ? IslandPalette.hoverSurface : IslandPalette.surface
    }

    var body: some View {
        configuration.label
            .font(IslandTypography.control)
            .foregroundStyle(isSelected || isHovered ? IslandPalette.title : IslandPalette.subtitle)
            .padding(.horizontal, 10)
            .padding(.vertical, isMultiline ? 8 : 0)
            .frame(minHeight: IslandLayout.controlHeight)
            .background(fill, in: RoundedRectangle(cornerRadius: isMultiline ? IslandLayout.cardRadius : IslandLayout.controlHeight / 2))
            .overlay {
                RoundedRectangle(cornerRadius: isMultiline ? IslandLayout.cardRadius : IslandLayout.controlHeight / 2)
                    .strokeBorder(isSelected ? IslandPalette.selectedBorder : IslandPalette.border, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: isMultiline ? IslandLayout.cardRadius : IslandLayout.controlHeight / 2))
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

/// A labeled single-choice group using the same selection treatment as panel navigation.
struct IslandChoiceGroup<Option: Hashable, Label: View>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option
    var fillsWidth = false
    @ViewBuilder let label: (Option) -> Label

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    label(option)
                        .frame(maxWidth: fillsWidth ? .infinity : nil)
                }
                .buttonStyle(IslandButtonStyle(isSelected: selection == option))
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

struct IslandCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(configuration.isOn ? IslandPalette.accent : IslandPalette.surface)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(configuration.isOn ? IslandPalette.selectedBorder : IslandPalette.subtitle, lineWidth: 1)
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(IslandPalette.onAccent)
                    }
                }
                .frame(width: 16, height: 16)
                configuration.label
                    .font(IslandTypography.body)
                    .foregroundStyle(IslandPalette.title)
            }
            .frame(minHeight: IslandLayout.controlHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Keep native checkbox role, value and activation for assistive technology.
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.checkbox)
        }
    }
}

/// Native menu selection keeps keyboard navigation, checked items and accessibility values.
struct IslandMenuPicker<Option: Hashable>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.self) { option in
                Text(label(option)).tag(option)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .font(IslandTypography.control)
        .frame(maxWidth: .infinity, minHeight: IslandLayout.controlHeight, alignment: .leading)
    }
}

/// Scroll container for the expanded island pages.
///
/// macOS draws overlay scrollers on top of the trailing edge of the scroll view, where cards
/// would otherwise sit. The shell's horizontal padding is reserved as that gutter: the scroll
/// view extends into the padding while the page keeps its current inset, so scrollers, including
/// the wider hover state, never cover card content. Legacy scrollers keep their own column and
/// stay clear of the content for the same reason.
struct IslandPanelScrollView<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            content
                .padding(.trailing, IslandLayout.panelPadding)
        }
        .padding(.trailing, -IslandLayout.panelPadding)
    }
}
