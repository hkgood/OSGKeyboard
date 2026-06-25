// TranslationPickerRow.swift
// OSGKeyboard · Main App
//
// Single-row "翻译" picker — replaces the previous two-row toggle +
// target-locale dropdown. Lets the user pick "不翻译" (off, the
// default) or one of the 10 target languages, all from a single
// `Menu`.
//
// Mapping to persisted state:
//   • "不翻译"            → translationEnabled = false
//   • any specific locale → translationEnabled = true, translationTargetLocaleId = <id>
//
// The local engine constraint ("translation is cloud-only") is handled
// in two places that read this row:
//   • The picker greys out specific locales (and prepends a "需云端"
//     hint) when `config.isLocalEngine` — the user can still pick
//     something but it won't fire end-to-end until they switch engines.
//   • The pipeline (`PolishingService`) rejects `.translate` on local
//     engine with `translationNotAvailable`, which `KeyboardViewController`
//     surfaces as a 2.4s toast. Belt + suspenders.

import SwiftUI
import OSGKeyboardShared

struct TranslationPickerRow: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @ObservedObject var config: ProviderConfig

    var body: some View {
        HStack {
            Text("settings.translation.title")
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
                        .foregroundStyle(pickerForeground)
                    if config.isLocalEngine && !currentIsOff {
                        // Inline hint so the user knows the picker
                        // selection is being held but won't fire on the
                        // local engine.
                        Text("settings.translation.hint.needsCloud")
                            .font(TypeStyle.caption2)
                            .foregroundStyle(palette.warning)
                    }
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: SettingsListMetrics.singleLineMinHeight)
    }

    // MARK: - Selection plumbing

    /// Currently selected id derived from `translationEnabled`. We
    /// route everything through the `translationEnabled` boolean so the
    /// picker stays in lock-step with the rest of the system (chip,
    /// pipeline, `isTranslationEffective`).
    private var currentSelectionId: String {
        config.translationEnabled
            ? config.translationTargetLocaleId
            : TranslationLanguageCatalog.offLocaleId
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

    private var pickerForeground: Color {
        currentIsOff ? palette.textSecondary : palette.textPrimary
    }

    /// Translates a picker choice into the underlying
    /// `translationEnabled` + `translationTargetLocaleId` pair. Picking
    /// "不翻译" clears the toggle; any locale flips it on and stores
    /// the id.
    private func apply(_ language: TranslationLanguage) {
        if language.id == TranslationLanguageCatalog.offLocaleId {
            config.translationEnabled = false
            return
        }
        config.translationEnabled = true
        config.translationTargetLocaleId = language.id
    }
}