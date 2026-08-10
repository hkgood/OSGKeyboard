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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themePalette) private var palette

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
                .background(buttonFill, in: Circle())
                .overlay(Circle().stroke(palette.divider, lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    private var buttonFill: Color {
        colorScheme == .dark ? Color(white: 0.30) : .white
    }
}

private enum KeyboardInputTab: CaseIterable {
    case ai
    case voice
    case chinese
    case english

    var title: String {
        switch self {
        case .ai: return "AI"
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
                            .frame(
                                width: tab == .english || tab == .ai ? 34 : 42,
                                height: 30
                            )
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
                    .opacity(tabOpacity(tab))
                    .accessibilityLabel(accessibilityLabel(for: tab))
                    .accessibilityAddTraits(isSelected(tab) ? .isSelected : [])
                }
            }
            .padding(2)
            .background(trackFill, in: Capsule())

            KeyboardClipboardMenuButton(
                palette: palette,
                action: state.openClipboardPanel
            )
            .equatable()
        }
    }

    private var selectedFill: Color {
        colorScheme == .dark ? Color(white: 0.38) : .white
    }

    private func tabOpacity(_ tab: KeyboardInputTab) -> Double {
        guard tab != .voice, !state.canEnterTypingSurface else { return 1 }
        if case .recording = state.phase {
            return 0
        }
        return 0.42
    }

    private var trackFill: Color {
        colorScheme == .dark ? Color(white: 0.18) : Color.black.opacity(0.08)
    }

    private var pressedFill: Color {
        colorScheme == .dark ? Color(white: 0.22) : Color(white: 0.84)
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
        case .ai: return "切换到 AI 问答"
        case .voice: return "切换到语音输入"
        case .chinese: return "切换到中文输入"
        case .english: return "切换到英文输入"
        }
    }
}

struct KeyboardTranslationMenuButton: View, Equatable {
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
            // Match the adjacent undo key: 44×44 rounded-rect chrome, not a circle chip.
            NativeKeyboardKeySurface(
                isPressed: false,
                fill: NativeKeyboardKeyColors.fill(for: colorScheme),
                pressedFill: NativeKeyboardKeyColors.pressedFill(for: colorScheme),
                border: palette.divider,
                cornerRadius: KeyboardChromeLayout.actionKeyCornerRadius
            ) {
                Image(systemName: isEnabled ? "character.bubble.fill" : "character.bubble")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        isEnabled
                            ? palette.accent
                            : NativeKeyboardKeyColors.text(for: colorScheme)
                    )
            }
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
