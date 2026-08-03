// KeyboardTopControls.swift
// OSGKeyboard · Keyboard Extension
//
// Shared top-right input switcher used by both voice and typing surfaces.
// The same footprint is replaced by candidates while Chinese is composing.

import SwiftUI
import OSGKeyboardShared

enum KeyboardTopBarMetrics {
    static let height: CGFloat = 44
    static let horizontalInset: CGFloat = 12
    /// TypingRootView already contributes 8 pt around the entire key surface.
    static let nestedHorizontalInset: CGFloat = horizontalInset - KeyboardChromeLayout.horizontalInset
    static let logoHeight: CGFloat = 22
    static let logoWidth: CGFloat = logoHeight * 952 / 291
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
        .accessibilityLabel(ExtL10n.text("keyboard.onboarding.api.openHostApp"))
    }
}

private enum KeyboardInputTab: CaseIterable {
    case voice
    case chinese
    case english

    var title: String {
        switch self {
        case .voice: return "语音"
        case .chinese: return "中文"
        case .english: return "EN"
        }
    }
}

struct KeyboardTopControls: View {
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var state: KeyboardState
    @ObservedObject var typing: TypingSessionController

    let palette: ThemePalette
    let onInsert: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(KeyboardInputTab.allCases, id: \.self) { tab in
                    Button {
                        select(tab)
                    } label: {
                        Text(tab.title)
                            .font(.system(size: 12, weight: isSelected(tab) ? .semibold : .medium))
                            .foregroundStyle(
                                isSelected(tab) ? palette.textPrimary : palette.textSecondary
                            )
                            .frame(width: tab == .english ? 34 : 42, height: 30)
                            .background {
                                if isSelected(tab) {
                                    Capsule()
                                        .fill(selectedFill)
                                        .shadow(
                                            color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.10),
                                            radius: 1.5,
                                            y: 1
                                        )
                                }
                            }
                    }
                    .buttonStyle(TopControlPressStyle(pressedFill: pressedFill))
                    .disabled(tab != .voice && !state.canEnterTypingSurface)
                    .opacity(tab != .voice && !state.canEnterTypingSurface ? 0.42 : 1)
                    .accessibilityLabel(accessibilityLabel(for: tab))
                    .accessibilityAddTraits(isSelected(tab) ? .isSelected : [])
                }
            }
            .padding(2)
            .background(trackFill, in: Capsule())

            KeyboardTranslationMenuButton(
                palette: palette,
                targetLocaleId: state.translationTargetLocaleId,
                onSelect: state.setTranslationTargetLocaleId
            )
            // Decouple the open picker from the keyboard's 1 Hz App Group
            // poll so scrolling does not reset or dismiss the menu.
            .equatable()
        }
    }

    private var selectedFill: Color {
        colorScheme == .dark ? Color(white: 0.38) : .white
    }

    private var trackFill: Color {
        colorScheme == .dark ? Color(white: 0.18) : Color.black.opacity(0.08)
    }

    private var pressedFill: Color {
        colorScheme == .dark ? Color(white: 0.22) : Color(white: 0.84)
    }

    private func isSelected(_ tab: KeyboardInputTab) -> Bool {
        switch tab {
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
        case .voice:
            state.setSurface(.voice)
        case .chinese:
            let raw = typing.setLanguage(.chinese)
            if !raw.isEmpty { onInsert(raw) }
            state.setSurface(.typing)
        case .english:
            let raw = typing.setLanguage(.english)
            if !raw.isEmpty { onInsert(raw) }
            state.setSurface(.typing)
        }
    }

    private func accessibilityLabel(for tab: KeyboardInputTab) -> String {
        switch tab {
        case .voice: return "切换到语音输入"
        case .chinese: return "切换到中文输入"
        case .english: return "切换到英文输入"
        }
    }
}

private struct KeyboardTranslationMenuButton: View, Equatable {
    @Environment(\.colorScheme) private var colorScheme

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
            Image(systemName: isEnabled ? "character.bubble.fill" : "character.bubble")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isEnabled ? palette.accent : palette.textSecondary)
                .frame(width: 34, height: 34)
                .background(buttonFill, in: Circle())
                .overlay(Circle().stroke(buttonStroke, lineWidth: 0.5))
        }
        .menuStyle(.button)
        .accessibilityLabel(Text(SharedL10n.string("keyboard.translation.a11y")))
        .accessibilityHint(Text(SharedL10n.string("keyboard.translation.a11yHint")))
    }

    private var buttonFill: Color {
        if isEnabled {
            return palette.accent.opacity(colorScheme == .dark ? 0.28 : 0.16)
        }
        return colorScheme == .dark ? Color(white: 0.30) : .white
    }

    private var buttonStroke: Color {
        isEnabled ? palette.accent.opacity(0.35) : palette.divider
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
