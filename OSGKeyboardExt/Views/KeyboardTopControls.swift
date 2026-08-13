// KeyboardTopControls.swift
// OSGKeyboard · Keyboard Extension
//
// Shared top-right input switcher used by both voice and typing surfaces.
// The same footprint is replaced by candidates while Chinese is composing.

import SwiftUI
import OSGKeyboardShared

private struct KeyboardTabSelectionNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var keyboardTabSelectionNamespace: Namespace.ID? {
        get { self[KeyboardTabSelectionNamespaceKey.self] }
        set { self[KeyboardTabSelectionNamespaceKey.self] = newValue }
    }
}

enum KeyboardTopBarMetrics {
    static let height: CGFloat = 44
    static let horizontalInset: CGFloat = 12
    /// TypingRootView already contributes 8 pt around the entire key surface.
    static let nestedHorizontalInset: CGFloat = horizontalInset - KeyboardChromeLayout.horizontalInset
    static let logoHeight: CGFloat = 22
    static let logoWidth: CGFloat = logoHeight * 952 / 291
    /// Shared footprint for top-trailing chips (clipboard, cancel/X, translation).
    static let trailingChipSize: CGFloat = 34
    static let trailingChipIconSize: CGFloat = 15
}

struct KeyboardBrandLogo: View {
    @Environment(\.colorScheme) private var colorScheme

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image("OSGLogoWide")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                .frame(
                    width: KeyboardTopBarMetrics.logoWidth,
                    height: KeyboardTopBarMetrics.logoHeight
                )
                .contentShape(Rectangle())
                .accessibilityHidden(true)
        }
        .buttonStyle(BrandLogoPressStyle())
        .accessibilityLabel(ExtL10n.text("keyboard.openSettingsA11y"))
    }
}

struct KeyboardCancelButton: View {
    @Environment(\.themePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    let action: () -> Void
    let accessibilityLabel: Text
    let accessibilityHint: Text

    var body: some View {
        // Same 34×34 chip as KeyboardClipboardMenuButton / translation.
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: KeyboardTopBarMetrics.trailingChipIconSize, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .frame(
                    width: KeyboardTopBarMetrics.trailingChipSize,
                    height: KeyboardTopBarMetrics.trailingChipSize
                )
                // 不透明键面色：玻璃时代靠折射显「实」，半透明实心会发淡。
                .background(NativeKeyboardKeyColors.fill(for: colorScheme), in: Circle())
                .overlay(
                    Circle().stroke(palette.divider, lineWidth: 0.5)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}

private enum KeyboardInputTab: CaseIterable {
    case ai
    case voice
    case chinese
    case english

    var title: String {
        switch self {
        case .ai: return ExtL10n.string("keyboard.tab.ai")
        case .voice: return ExtL10n.string("keyboard.tab.voice")
        case .chinese: return ExtL10n.string("keyboard.tab.chinese")
        case .english: return ExtL10n.string("keyboard.tab.english")
        }
    }
}

struct KeyboardTopControls: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.keyboardTabSelectionNamespace) private var sharedSelectionNamespace
    @Namespace private var fallbackSelectionNamespace

    @ObservedObject var state: KeyboardState
    @ObservedObject var typing: TypingSessionController

    let palette: ThemePalette
    let onInsert: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            // 分段轨道：不透明灰底；选中项用白/升高键面滑动，避免半透明发淡。
            HStack(spacing: 2) {
                ForEach(KeyboardInputTab.allCases, id: \.self) { tab in
                    tabButton(tab)
                }
            }
            .padding(2)
            .background(tabTrackFill, in: Capsule())
            .overlay(
                Capsule().stroke(palette.divider, lineWidth: 0.5)
            )

            if state.canShowClipboardEntry {
                KeyboardClipboardMenuButton(
                    palette: palette,
                    action: state.openClipboardPanel
                )
                .equatable()
            }
        }
    }

    private func tabButton(_ tab: KeyboardInputTab) -> some View {
        let selected = isSelected(tab)
        let width: CGFloat = tab == .english || tab == .ai ? 34 : 42

        return Button {
            withAnimation(Motion.soft) {
                select(tab)
            }
        } label: {
            tabLabel(tab, selected: selected, width: width)
        }
        .buttonStyle(TopControlPressStyle(pressedFill: pressedFill))
        .disabled(tab != .voice && !state.canEnterTypingSurface)
        .opacity(tabOpacity(tab))
        .accessibilityLabel(accessibilityLabel(for: tab))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func tabLabel(
        _ tab: KeyboardInputTab,
        selected: Bool,
        width: CGFloat
    ) -> some View {
        let label = Text(tab.title)
            .font(.system(size: 12, weight: selected ? .semibold : .medium))
            .foregroundStyle(selected ? palette.textPrimary : palette.textSecondary)
            .frame(width: width, height: 30)

        if selected {
            let namespace = sharedSelectionNamespace ?? fallbackSelectionNamespace
            // 去玻璃但保留滑动高亮：不透明键面胶囊在标签间平滑移动。
            label.background(
                Capsule()
                    .fill(NativeKeyboardKeyColors.fill(for: colorScheme))
                    .overlay(Capsule().stroke(palette.divider, lineWidth: 0.5))
                    .matchedGeometryEffect(id: "keyboard-tab-selection", in: namespace)
            )
        } else {
            label
        }
    }

    private func tabOpacity(_ tab: KeyboardInputTab) -> Double {
        guard tab != .voice, !state.canEnterTypingSurface else { return 1 }
        if case .recording = state.phase {
            return 0
        }
        return 0.42
    }

    private var pressedFill: Color {
        colorScheme == .dark ? Color(white: 0.22) : Color(white: 0.84)
    }

    /// 分段轨道底色：不透明，且与选中键面（NativeKeyboardKeyColors.fill）拉开明度，
    /// 深色下压暗、浅色下提亮，让滑动的选中项始终清晰可辨。
    private var tabTrackFill: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.87)
    }

    private func isSelected(_ tab: KeyboardInputTab) -> Bool {
        switch tab {
        case .ai:
            return state.surface == .ai
        case .voice:
            return state.surface == .voice
        case .chinese:
            return state.surface == .typing && typing.language == .chinese
        case .english:
            return state.surface == .typing && typing.language == .english
        }
    }

    private func select(_ tab: KeyboardInputTab) {
        switch tab {
        case .ai:
            state.setSurface(.ai)
        case .voice:
            state.setSurface(.voice)
        case .chinese:
            applyTypingOutput(typing.setLanguage(.chinese))
            state.setSurface(.typing)
        case .english:
            applyTypingOutput(typing.setLanguage(.english))
            state.setSurface(.typing)
        }
    }

    private func applyTypingOutput(_ output: TypingOutput) {
        if output.deleteCount > 0 {
            // Language switch rarely deletes; keep insert-only path for capsule.
        }
        guard !output.text.isEmpty else {
            typing.syncAutocapitalization()
            return
        }
        onInsert(output.text)
        typing.syncAutocapitalization(
            accountingForInsert: output.text,
            deleteCount: output.deleteCount
        )
    }

    private func accessibilityLabel(for tab: KeyboardInputTab) -> String {
        switch tab {
        case .ai: return ExtL10n.string("keyboard.tab.ai.a11y")
        case .voice: return ExtL10n.string("keyboard.tab.voice.a11y")
        case .chinese: return ExtL10n.string("keyboard.tab.chinese.a11y")
        case .english: return ExtL10n.string("keyboard.tab.english.a11y")
        }
    }
}

struct KeyboardTranslationMenuButton: View, Equatable {
    let palette: ThemePalette
    let targetLocaleId: String
    let onSelect: (String) -> Void

    nonisolated static func == (
        lhs: KeyboardTranslationMenuButton,
        rhs: KeyboardTranslationMenuButton
    ) -> Bool {
        lhs.palette == rhs.palette && lhs.targetLocaleId == rhs.targetLocaleId
    }

    private var isEnabled: Bool {
        targetLocaleId != TranslationLanguageCatalog.offLocaleId
    }

    var body: some View {
        Menu {
            ForEach(TranslationLanguageCatalog.all) { language in
                Button {
                    onSelect(language.id)
                } label: {
                    if language.id == targetLocaleId {
                        Label(displayLabel(for: language), systemImage: "checkmark")
                    } else {
                        Text(displayLabel(for: language))
                    }
                }
            }
        } label: {
            ZStack {
                Color.clear
                Image(systemName: isEnabled ? "character.bubble.fill" : "character.bubble")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(
                        isEnabled
                            ? palette.accent
                            : palette.textSecondary
                    )
            }
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: Circle())
        }
        .menuStyle(.button)
        .accessibilityLabel(Text(SharedL10n.string("keyboard.translation.a11y")))
        .accessibilityHint(Text(SharedL10n.string("keyboard.translation.a11yHint")))
    }

    private func displayLabel(for language: TranslationLanguage) -> String {
        if language.id == TranslationLanguageCatalog.offLocaleId {
            return SharedL10n.string("keyboard.translation.offMenu")
        }
        return language.nativeName
    }
}

private struct BrandLogoPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.62 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct TopControlPressStyle: ButtonStyle {
    let pressedFill: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? pressedFill.opacity(0.55) : .clear)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
