// TranslationPickerRow.swift
// OSGKeyboard · Main App
//
// Single-row "翻译" picker — replaces the previous two-row toggle +
// target-locale dropdown. Lets the user pick "不翻译" (off, the
// default) or one of the 10 target languages, all from a single
// `Menu`.
//
// v0.2.1 follow-up: row is rendered through an `isVisible` parameter
// so callers (`SettingsView`, `OnboardingView`) can drop the row
// entirely when the engine can't run the cloud translate-and-polish
// step (`ProviderConfig.isTranslationRowVisible`). The "needs cloud"
// inline hint was deleted along with the previous Bool toggle — the
// user only sees the row when the engine can act on the choice.
//
// v0.2.1 final review: both engines now run the translate-and-polish
// step (the local engine routes through DeepSeek via
// `ProviderConfig.localModeProviderId`), so the row title changed
// from "Translation" to "Polish then translate" to match the new
// always-on translation contract.
//
// Mapping to persisted state:
//   • "不翻译"            → translationTargetLocaleId = "off"
//   • any specific locale → translationTargetLocaleId = <id>
//
// The pipeline (`PolishingService`) honors `.translate` on both
// engines when this row is visible — no more "rejected mode" toast.

import SwiftUI
import OSGKeyboardShared

struct TranslationPickerRow: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @ObservedObject var config: ProviderConfig

    /// Visibility flag — when `false` the row renders as `EmptyView`
    /// (callers can also wrap the call site in `if` for symmetry, but
    /// having the guard here means a forgotten `if` still produces a
    /// safe no-op rather than a leaked dead row).
    var isVisible: Bool = true

    var body: some View {
        if isVisible {
            HStack {
                Text("settings.translation.afterPolish")
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Menu {
                    ForEach(TranslationLanguageCatalog.all) { language in
                        Button {
                            apply(language)
                        } label: {
                            if currentSelectionId == language.id {
                                Label(displayLabel(for: language), systemImage: "checkmark")
                            } else {
                                Text(displayLabel(for: language))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(currentLabel)
                            .font(TypeStyle.body)
                            .foregroundStyle(currentIsOff ? palette.textSecondary : palette.textPrimary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: SettingsListMetrics.singleLineMinHeight)
        }
    }

    // MARK: - Selection plumbing

    /// Currently selected id — the picker always reads
    /// `translationTargetLocaleId` directly (the previous
    /// `translationEnabled` boolean is now derived from it).
    private var currentSelectionId: String {
        config.translationTargetLocaleId
    }

    private var currentLabel: String {
        displayLabel(for: TranslationLanguageCatalog.resolve(currentSelectionId))
    }

    private var currentIsOff: Bool {
        TranslationLanguageCatalog.isOff(currentSelectionId)
    }

    private func displayLabel(for language: TranslationLanguage) -> String {
        if language.id == TranslationLanguageCatalog.offLocaleId {
            return AppL10n.string("settings.translation.off")
        }
        return language.nativeName
    }

    /// Translates a picker choice into a single persisted field.
    /// "不翻译" writes `offLocaleId`; any concrete locale writes its
    /// id. `ProviderConfig.translationEnabled` is derived from the
    /// resulting value, so callers don't need to flip a separate Bool.
    private func apply(_ language: TranslationLanguage) {
        config.translationTargetLocaleId = language.id
    }
}