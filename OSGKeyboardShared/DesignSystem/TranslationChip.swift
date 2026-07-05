// TranslationChip.swift
// OSGKeyboard · Shared
//
// Translation target picker chip shared between keyboard extension and
// host-app preview surfaces.

import SwiftUI

public struct TranslationChip: View, Equatable {
    public let palette: ThemePalette
    public let targetLocaleId: String
    public let onSelect: (String) -> Void

    public init(
        palette: ThemePalette,
        targetLocaleId: String,
        onSelect: @escaping (String) -> Void
    ) {
        self.palette = palette
        self.targetLocaleId = targetLocaleId
        self.onSelect = onSelect
    }

    nonisolated public static func == (lhs: TranslationChip, rhs: TranslationChip) -> Bool {
        lhs.palette == rhs.palette && lhs.targetLocaleId == rhs.targetLocaleId
    }

    public var body: some View {
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
            label
        }
        .menuStyle(.button)
        .accessibilityLabel(Text(SharedL10n.string("keyboard.translation.a11y")))
        .accessibilityHint(Text(SharedL10n.string("keyboard.translation.a11yHint")))
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
            return SharedL10n.string("keyboard.translation.offMenu")
        }
        return language.nativeName
    }

    private func chipLabel(target: TranslationLanguage, enabled: Bool) -> String {
        if !enabled {
            return SharedL10n.string("keyboard.translation.chip")
        }
        return "→\(shortLabel(for: target))"
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
        enabled ? palette.accent : palette.textPrimary
    }

    private func background(enabled: Bool) -> Color {
        enabled ? palette.accent.opacity(0.15) : palette.surfaceElevated
    }

    private func stroke(enabled: Bool) -> Color {
        enabled ? palette.accent.opacity(0.35) : palette.divider
    }
}
