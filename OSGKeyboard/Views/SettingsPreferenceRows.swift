// SettingsPreferenceRows.swift
// OSGKeyboard · Main App
//
// Shared preference picker / toggle rows used by Settings home and
// secondary pages (General, Voice session, Daily).

import SwiftUI
import Speech
import OSGKeyboardShared

// MARK: - App language picker row

struct AppLanguagePickerRow: View {
    @Binding var selection: AppUILanguage

    private var options: [(id: String, label: String)] {
        AppUILanguage.allCases.map { language in
            (language.rawValue, AppL10n.string(language.labelKey))
        }
    }

    var body: some View {
        SettingsMenuPickerRow(
            title: AppL10n.string("settings.appLanguage.title"),
            options: options,
            selection: Binding(
                get: { selection.rawValue },
                set: { newValue in
                    selection = AppUILanguage(rawValue: newValue) ?? .auto
                }
            )
        )
    }
}

// MARK: - Appearance picker row

struct AppearancePickerRow: View {
    @AppStorage(AppearancePreference.storageKey)
    private var appearanceRaw = AppearancePreference.system.rawValue

    private var options: [(id: String, label: String)] {
        AppearancePreference.allCases.map { preference in
            (preference.rawValue, AppL10n.string(preference.labelKey))
        }
    }

    var body: some View {
        SettingsMenuPickerRow(
            title: AppL10n.string("settings.appearance.title"),
            options: options,
            selection: $appearanceRaw
        )
    }
}

// MARK: - Handedness picker row

struct HandednessPickerRow: View {
    @Binding var selection: HandednessPreference

    private var options: [(id: String, label: String)] {
        HandednessPreference.allCases.map { preference in
            (preference.rawValue, AppL10n.string(preference.labelKey))
        }
    }

    var body: some View {
        SettingsMenuPickerRow(
            title: AppL10n.string("settings.handedness.title"),
            options: options,
            selection: Binding(
                get: { selection.rawValue },
                set: { newValue in
                    selection = HandednessPreference(rawValue: newValue) ?? .left
                }
            )
        )
    }
}

// MARK: - Keyboard haptic picker row

struct KeyboardHapticPickerRow: View {
    @Binding var selection: KeyboardHapticIntensity

    private var options: [(id: String, label: String)] {
        KeyboardHapticIntensity.allCases.map { intensity in
            (intensity.rawValue, AppL10n.string(intensity.labelKey))
        }
    }

    var body: some View {
        SettingsMenuPickerRow(
            title: AppL10n.string("settings.keyboardHaptic.title"),
            options: options,
            selection: Binding(
                get: { selection.rawValue },
                set: { newValue in
                    selection = KeyboardHapticIntensity(rawValue: newValue) ?? .default
                }
            )
        )
    }
}

// MARK: - Polish intensity picker row

struct PolishIntensityPickerRow: View {
    @ObservedObject var config: ProviderConfig

    var body: some View {
        SettingsMenuPickerRow(
            title: AppL10n.string("settings.polishIntensity.title"),
            options: PolishIntensity.allCases.map { intensity in
                (
                    intensity.rawValue,
                    SharedL10n.string(intensity.labelKey, language: config.uiLanguage)
                )
            },
            selection: Binding(
                get: { config.polishIntensity.rawValue },
                set: { rawValue in
                    config.polishIntensity = PolishIntensity(rawValue: rawValue) ?? .default
                }
            )
        )
    }
}

// MARK: - Default input surface toggle

struct DefaultTypingInputToggleRow: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @ObservedObject private var config = ProviderConfig.shared
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(AppL10n.string("settings.typingInput.default.title", language: config.uiLanguage))
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                Text(AppL10n.string("settings.typingInput.default.description", language: config.uiLanguage))
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(palette.accent)
        .settingsListRow()
    }
}

struct RememberLastSurfaceToggleRow: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @ObservedObject private var config = ProviderConfig.shared
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(AppL10n.string("settings.typingInput.rememberLast.title", language: config.uiLanguage))
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                Text(AppL10n.string("settings.typingInput.rememberLast.description", language: config.uiLanguage))
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(palette.accent)
        .settingsListRow()
    }
}

// MARK: - Cursor drag navigation toggle

struct CursorDragNavigationToggleRow: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text("settings.cursorDragNavigation.title")
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
        }
        .tint(palette.accent)
        .settingsListRow()
    }
}

// MARK: - Menu picker row (generic)

struct SettingsMenuPickerRow: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    let title: String
    let options: [(id: String, label: String)]
    @Binding var selection: String

    var body: some View {
        HStack {
            Text(title)
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Menu {
                ForEach(options, id: \.id) { o in
                    Button {
                        selection = o.id
                    } label: {
                        if o.id == selection {
                            Label(o.label, systemImage: "checkmark")
                        } else {
                            Text(o.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentLabel)
                        .font(TypeStyle.body)
                        .foregroundStyle(palette.textSecondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .settingsListRow()
    }

    private var currentLabel: String {
        options.first(where: { $0.id == selection })?.label ?? "—"
    }
}

// MARK: - Locale picker row (with on-device indicator)

struct LocalePickerRow: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @ObservedObject private var config = ProviderConfig.shared

    let locales: [(id: String, onDevice: Bool)]
    @Binding var selection: String

    var body: some View {
        HStack {
            Text("settings.asrLocale")
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Menu {
                ForEach(locales, id: \.id) { locale in
                    Button {
                        selection = locale.id
                    } label: {
                        // iOS Menu converts SwiftUI Label to UIAction (title + image).
                        // Using Label keeps checkmark + on-device icon both visible.
                        let name = label(for: locale.id)
                        if locale.id == selection {
                            Label(name, systemImage: "checkmark")
                        } else if locale.onDevice {
                            Label(name, systemImage: "iphone")
                        } else {
                            Text(name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    // On-device badge for the currently selected locale.
                    if let current = locales.first(where: { $0.id == selection }), current.onDevice {
                        Image(systemName: "iphone")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.accent)
                    }
                    Text(currentLabel)
                        .font(TypeStyle.body)
                        .foregroundStyle(palette.textSecondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .settingsListRow()
    }

    private func label(for localeId: String) -> String {
        ASRLocaleLabels.displayName(for: localeId, language: config.uiLanguage)
    }

    private var currentLabel: String {
        label(for: selection)
    }
}

// MARK: - Dynamic ASR locale loading

enum SettingsASRLocales {
    /// Falls back to a short static list while `SFSpeechRecognizer` is loading.
    static let staticFallback: [(id: String, onDevice: Bool)] = [
        ("auto", false),
        ("zh-Hans", false),
        ("zh-Hant", false),
        ("en-US", false),
        ("ja-JP", false),
        ("ko-KR", false),
    ]

    static func loadDynamic() async -> [(id: String, onDevice: Bool)] {
        // Run everything in a background task: `SFSpeechRecognizer.supportedLocales()`
        // can return 100+ locales, and we probe supportsOnDeviceRecognition for each.
        // Creating `SFSpeechRecognizer` instances in a @Sendable closure is
        // safe here; we only read locale metadata (no transcription session).
        await Task.detached(priority: .userInitiated) {
            var result: [(id: String, onDevice: Bool)] = [("auto", false)]

            for locale in SFSpeechRecognizer.supportedLocales()
                .sorted(by: { $0.identifier < $1.identifier }) {
                let id = locale.identifier
                let onDevice = SFSpeechRecognizer(locale: locale)?.supportsOnDeviceRecognition ?? false
                result.append((id: id, onDevice: onDevice))
            }
            return result
        }.value
    }
}
