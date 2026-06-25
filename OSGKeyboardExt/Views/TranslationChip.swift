// TranslationChip.swift
// OSGKeyboard · Keyboard Extension
//
// Compact chip rendered to the right of `LocaleChip` on the keyboard
// top bar. Doubles as both the on/off switch and the target-language
// picker — same Menu pattern as `LocaleChip` so muscle memory transfers.
//
// v0.2.1 follow-up: removed the explicit on/off toggle entry. The
// chip is now a pure picker over the 11 catalog rows (off + 10
// locales); selecting "不翻译" turns translation off, selecting any
// locale turns it on with that target. `translationEnabled` is
// derived from the locale id so the chip / pipeline read the same
// source of truth.
//
// v0.2.1 final review: dropped the "needs cloud" warning state —
// both engines now run the translate-and-polish step (the local
// engine routes through DeepSeek via
// `ProviderConfig.localModeProviderId`). The chip is therefore just
// off / on, with the same accent treatment either way.
//
// Visual states:
//   • off             → dim outline, "翻译" label
//   • on (any engine) → accent fill, "→ EN" / "→ 日本語" style label
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
            // v0.2.1 follow-up: pure picker over the full catalog,
            // including `offLocaleId` at the top so "turn off" is one
            // tap from any enabled state. Picking a row writes
            // `translationTargetLocaleId`; `translationEnabled` is
            // derived from it.
            ForEach(TranslationLanguageCatalog.all) { language in
                Button {
                    state.setTranslationTargetLocaleId(language.id)
                } label: {
                    if language.id == currentSelectionId {
                        Label(displayLabel(for: language), systemImage: "checkmark")
                    } else {
                        Text(displayLabel(for: language))
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

    /// Active selection id — the chip derives "on" from a non-off
    /// locale id, so reading `translationTargetLocaleId` is enough.
    private var currentSelectionId: String {
        state.translationTargetLocaleId
    }

    private func displayLabel(for language: TranslationLanguage) -> String {
        if language.id == TranslationLanguageCatalog.offLocaleId {
            return ExtL10n.string("keyboard.translation.off")
        }
        return language.nativeName
    }

    private func chipLabel(target: TranslationLanguage, enabled: Bool, isLocal: Bool) -> String {
        // v0.2.1 follow-up: with the local engine now routing the
        // polish / translate step through DeepSeek, the chip shows
        // the same "→EN"-style label on both engines. There's no
        // "needs cloud" hint path anymore.
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
        // v0.2.1 follow-up: the chip no longer needs a "warning" path
        // for local + on — both engines share the accent treatment
        // now. `isLocal` is kept in the signature so callers don't
        // need to change; it's intentionally unused below.
        _ = isLocal
        if enabled { return palette.accent }
        return palette.textPrimary
    }

    private func background(enabled: Bool, isLocal: Bool) -> Color {
        _ = isLocal
        if enabled { return palette.accent.opacity(0.15) }
        return palette.surfaceElevated
    }

    private func stroke(enabled: Bool, isLocal: Bool) -> Color {
        _ = isLocal
        if enabled { return palette.accent.opacity(0.35) }
        return palette.divider
    }
}