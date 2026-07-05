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
//   • off             → dim outline, "翻译" chip label (menu first row = "不翻译")
//   • on (any engine) → accent fill, "→ EN" / "→ 日本語" style label
//
// Stays in the same visual family as `CloudEngineChip` / `LocaleChip`
// (Capsule + 28 pt min height + 6 pt vertical padding) so the top bar
// doesn't grow when translation is enabled.

import SwiftUI
import OSGKeyboardShared

struct TranslationChip: View, Equatable {
    /// Passed in as a value (not read from `@Environment`) so the chip can
    /// be wrapped in `.equatable()` at the call site: `EquatableView`
    /// suppresses environment-driven refreshes, so injecting the palette
    /// here keeps colours correct across dark/light switches.
    let palette: ThemePalette
    /// The active target-locale id (`offLocaleId` == translation off).
    let targetLocaleId: String
    /// Writes the picked locale id — wired to `state.setTranslationTargetLocaleId`.
    let onSelect: (String) -> Void

    /// Only `palette` and `targetLocaleId` drive the visuals; the
    /// `onSelect` closure is deliberately excluded from equality. Because
    /// the keyboard polls the App Group at 1 Hz (each poll re-publishes the
    /// `KeyboardState`), the parent view re-renders every second. Without
    /// this, SwiftUI would rebuild the `Menu` on every poll — dismissing an
    /// open picker or snapping its scroll position back to the top. With
    /// `.equatable()` the picker is rebuilt only on a real state change.
    nonisolated static func == (lhs: TranslationChip, rhs: TranslationChip) -> Bool {
        lhs.palette == rhs.palette && lhs.targetLocaleId == rhs.targetLocaleId
    }

    var body: some View {
        Menu {
            // v0.2.1 follow-up: pure picker over the full catalog,
            // including `offLocaleId` at the top so "turn off" is one
            // tap from any enabled state. Picking a row writes
            // `translationTargetLocaleId`; `translationEnabled` is
            // derived from it.
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
            label
        }
        .menuStyle(.button)
        .accessibilityLabel(ExtL10n.text("keyboard.translation.a11y"))
        .accessibilityHint(ExtL10n.text("keyboard.translation.a11yHint"))
    }

    @ViewBuilder
    private var label: some View {
        let target = TranslationLanguageCatalog.resolve(targetLocaleId)
        let enabled = targetLocaleId != TranslationLanguageCatalog.offLocaleId

        HStack(spacing: 4) {
            Image(systemName: enabled ? "character.bubble" : "character.bubble.fill")
            Text(chipLabel(target: target, enabled: enabled))
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .font(TypeStyle.caption2)
        .foregroundStyle(foreground(enabled: enabled))
        .padding(.horizontal, Spacing.xs + 2)
        .padding(.vertical, 6)
        .frame(minHeight: 28)
        .background(background(enabled: enabled), in: Capsule())
        .overlay(Capsule().stroke(stroke(enabled: enabled), lineWidth: 0.5))
    }

    private func displayLabel(for language: TranslationLanguage) -> String {
        if language.id == TranslationLanguageCatalog.offLocaleId {
            return ExtL10n.string("keyboard.translation.offMenu")
        }
        return language.nativeName
    }

    private func chipLabel(target: TranslationLanguage, enabled: Bool) -> String {
        if !enabled {
            return ExtL10n.string("keyboard.translation.chip")
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

    private func foreground(enabled: Bool) -> Color {
        if enabled { return palette.accent }
        return palette.textPrimary
    }

    private func background(enabled: Bool) -> Color {
        if enabled { return palette.accent.opacity(0.15) }
        return palette.surfaceElevated
    }

    private func stroke(enabled: Bool) -> Color {
        if enabled { return palette.accent.opacity(0.35) }
        return palette.divider
    }
}