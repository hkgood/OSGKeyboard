// TranslationPickerRow.swift
// OSGKeyboard · Main App
//
// List row that hosts the translation toggle + target-language picker.
// Lives at the bottom of the language tab in Settings (see
// `SettingsView.languageAndModelsSection`) so it sits right next to
// the existing ASR locale picker — same picker family, same row
// metrics.
//
// Layout:
//   • First row  → switch (label on the left, switch on the right)
//   • When on    → a second row with a Menu picker for the target
//     language. Disabled when the local engine is active so the user
//     immediately sees why the picker is greyed out (instead of picking
//     a target that the pipeline silently ignores).
//
// Reuses the host app's `ProviderConfig` `translationEnabled` /
// `translationTargetLocaleId` bindings — no new state, no new
// persistence path.

import SwiftUI
import OSGKeyboardShared

struct TranslationPickerRow: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @ObservedObject var config: ProviderConfig

    var body: some View {
        VStack(spacing: 0) {
            toggleRow
            if config.translationEnabled {
                Divider().background(palette.divider)
                targetRow
            }
        }
    }

    private var toggleRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("settings.translation.title")
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                Text(subtitleKey)
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Toggle(
                "",
                isOn: Binding(
                    get: { config.translationEnabled },
                    set: { config.translationEnabled = $0 }
                )
            )
            .labelsHidden()
            .tint(palette.accent)
        }
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: SettingsListMetrics.singleLineMinHeight)
    }

    /// Subtitle explains why the toggle is functionally inert when the
    /// local engine is on. We still let the user flip the toggle in
    /// that case so their preference is saved — the moment they switch
    /// back to cloud, translation just works.
    private var subtitleKey: LocalizedStringKey {
        config.isLocalEngine
            ? "settings.translation.subtitle.needsCloud"
            : "settings.translation.subtitle"
    }

    private var targetRow: some View {
        HStack {
            Text("settings.translation.target")
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Menu {
                ForEach(TranslationLanguageCatalog.all) { language in
                    Button {
                        config.translationTargetLocaleId = language.id
                    } label: {
                        if language.id == config.translationTargetLocaleId {
                            Label(language.nativeName, systemImage: "checkmark")
                        } else {
                            Text(language.nativeName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(currentTargetName)
                        .font(TypeStyle.body)
                        .foregroundStyle(pickerForeground)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .disabled(config.isLocalEngine)
            .opacity(config.isLocalEngine ? 0.5 : 1.0)
        }
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: SettingsListMetrics.singleLineMinHeight)
    }

    private var currentTargetName: String {
        TranslationLanguageCatalog.resolve(config.translationTargetLocaleId).nativeName
    }

    private var pickerForeground: Color {
        config.isLocalEngine ? palette.textTertiary : palette.textSecondary
    }
}