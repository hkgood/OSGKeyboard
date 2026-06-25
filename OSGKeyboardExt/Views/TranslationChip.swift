// TranslationChip.swift
// OSGKeyboard · Keyboard Extension
//
// Compact chip rendered to the right of `LocaleChip` on the keyboard
// top bar. Doubles as both the on/off switch and the target-language
// picker — same Menu pattern as `LocaleChip` so muscle memory transfers.
//
// Visual states:
//   • disabled              → dim outline, "翻译" label
//   • enabled + cloud       → accent fill, "→ EN" / "→ 日本語" style label
//   • enabled + local engine→ warning fill + "翻译需云端" hint (effectively
//     inert; the pipeline rejects the mode and the controller surfaces
//     the error toast)
//
// Stays in the same visual family as `CloudEngineChip` / `LocaleChip`
// (Capsule + 26 pt min height + 5 pt vertical padding) so the top bar
// doesn't grow when translation is enabled.

import SwiftUI
import OSGKeyboardShared

struct TranslationChip: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject var state: KeyboardViewController.State

    var body: some View {
        Menu {
            // Toggle entry sits at the top so the user can flip the feature
            // without picking a language first.
            Button {
                state.setTranslationEnabled(!state.translationEnabled)
            } label: {
                if state.translationEnabled {
                    Label(ExtL10n.string("keyboard.translation.disable"), systemImage: "checkmark")
                } else {
                    Text(ExtL10n.string("keyboard.translation.enable"))
                }
            }
            if state.translationEnabled {
                Divider()
                ForEach(TranslationLanguageCatalog.all) { language in
                    Button {
                        state.setTranslationTargetLocaleId(language.id)
                    } label: {
                        if language.id == state.translationTargetLocaleId {
                            Label(language.nativeName, systemImage: "checkmark")
                        } else {
                            Text(language.nativeName)
                        }
                    }
                }
            }
        } label: {
            label
        }
        .menuStyle(.button)
        .accessibilityLabel(ExtL10n.text("keyboard.translation.a11y"))
        .accessibilityHint(ExtL10n.text("keyboard.translation.a11yHint"))
    }

    @ViewBuilder
    private var label: some View {
        let target = TranslationLanguageCatalog.resolve(state.translationTargetLocaleId)
        let isLocal = state.isLocalEngine
        let enabled = state.translationEnabled

        HStack(spacing: 4) {
            Image(systemName: enabled ? "character.bubble" : "character.bubble.fill")
            Text(chipLabel(target: target, enabled: enabled, isLocal: isLocal))
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .font(TypeStyle.caption2)
        .foregroundStyle(foreground(enabled: enabled, isLocal: isLocal))
        .padding(.horizontal, Spacing.xs + 2)
        .padding(.vertical, 5)
        .frame(minHeight: 26)
        .background(background(enabled: enabled, isLocal: isLocal), in: Capsule())
        .overlay(Capsule().stroke(stroke(enabled: enabled, isLocal: isLocal), lineWidth: 0.5))
    }

    private func chipLabel(target: TranslationLanguage, enabled: Bool, isLocal: Bool) -> String {
        // Local-engine + on shows the constraint hint instead of the
        // target label so the user knows why nothing's happening.
        if enabled, isLocal {
            return ExtL10n.string("keyboard.translation.needsCloudShort")
        }
        if !enabled {
            return ExtL10n.string("keyboard.translation.off")
        }
        // Short form: "→EN" / "→日" style. Falls back to the prompt
        // language name for languages without a chip-style abbreviation
        // (e.g. French → "FR" via the 2-letter prefix).
        let short = shortLabel(for: target)
        return "→\(short)"
    }

    private func shortLabel(for target: TranslationLanguage) -> String {
        switch target.id {
        case "en":       return "EN"
        case "zh-Hans":  return "中"
        case "zh-Hant":  return "繁"
        case "ja":       return "日"
        case "ko":       return "韩"
        case "fr":       return "FR"
        case "de":       return "DE"
        case "es":       return "ES"
        case "ru":       return "RU"
        case "pt":       return "PT"
        default:         return target.promptLanguageName
        }
    }

    private func foreground(enabled: Bool, isLocal: Bool) -> Color {
        if enabled, isLocal { return palette.warning }
        if enabled { return palette.accent }
        return palette.textPrimary
    }

    private func background(enabled: Bool, isLocal: Bool) -> Color {
        if enabled, isLocal { return palette.warning.opacity(0.15) }
        if enabled { return palette.accent.opacity(0.15) }
        return palette.surfaceElevated
    }

    private func stroke(enabled: Bool, isLocal: Bool) -> Color {
        if enabled, isLocal { return palette.warning.opacity(0.35) }
        if enabled { return palette.accent.opacity(0.35) }
        return palette.divider
    }
}