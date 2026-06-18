// SettingsView.swift
// OSGKeyboard · Main App
//
// Sheet that hosts the API configuration. Single scrollable column, every
// field earns its space.

import SwiftUI
import Speech
import OSGKeyboardShared

struct SettingsView: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject var config = ProviderConfig.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showResetConfirm = false

    // Dynamic locale list loaded from SFSpeechRecognizer on first appear.
    @State private var dynamicLocales: [(id: String, label: String, onDevice: Bool)] = []

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: Spacing.md) {
                        engineSection
                        if config.engineMode == "cloud" {
                            providerSection
                            apiSection
                        }
                        languageSection
                        if config.engineMode == "cloud" {
                            promptSection
                        }
                        resetButton
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.md)
                }
            }
            .navigationTitle("设置 · Settings")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadDynamicLocales() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成 · Done") { dismiss() }
                        .font(TypeStyle.headline)
                        .foregroundStyle(palette.accent)
                }
            }
        }
        .confirmationDialog(
            "重置所有设置? · Reset all settings?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("重置 · Reset", role: .destructive) {
                config.reset()
            }
            Button("取消 · Cancel", role: .cancel) {}
        } message: {
            Text("API key、model 和 base URL 都会被清空。\nAPI key, model, and base URL will be cleared.")
        }
    }

    // MARK: - Engine

    private var localEngineSubtitle: String {
        if #available(iOS 26, *) {
            return "SpeechAnalyzer · 始终端侧，无需联网 · Always on-device, no network"
        } else {
            return "端侧 ASR · 仅转录，无润色 · On-device ASR, transcription only, no polish"
        }
    }

    private var engineSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("引擎 · Engine", subtitle: "选择识别方式。本地引擎无需 API Key，仅做语音转录。\nPick the recognition engine. Local engine does transcription only, no API key needed.")
            VStack(spacing: 0) {
                engineOptionRow(
                    id: "local",
                    icon: "iphone.badge.checkmark",
                    title: "本地识别",
                    subtitle: localEngineSubtitle
                )
                Divider().background(palette.divider)
                engineOptionRow(
                    id: "cloud",
                    icon: "wand.and.stars",
                    title: "云端润色",
                    subtitle: "ASR 转录 + LLM 润色，需要 API Key · ASR + LLM polish, API key required"
                )
            }
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .stroke(palette.divider, lineWidth: 0.5)
            )
        }
    }

    private func engineOptionRow(id: String, icon: String, title: String, subtitle: String) -> some View {
        let isSelected = config.engineMode == id
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                config.engineMode = id
                // Lock mode to transcribe when switching to local engine
                if id == "local" { config.modeId = "transcribe" }
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? palette.accent : palette.textSecondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(TypeStyle.body)
                        .foregroundStyle(isSelected ? palette.accent : palette.textPrimary)
                    Text(subtitle)
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.accent)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Provider

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("Provider · 提供商", subtitle: "选择 LLM 提供商。Pick the LLM that polishes your dictation.")
            ProviderPickerSection(config: config)
        }
    }

    // MARK: - API

    private var apiSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("API · 接口", subtitle: nil)
            APISettingsCard(config: config)
        }
    }

    // MARK: - Language (ASR + mode)

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("Language · 语言", subtitle: "选择识别语言\(config.engineMode == "cloud" ? "和文字处理模式" : "")。Recognition language\(config.engineMode == "cloud" ? " and text processing mode" : "").")
            VStack(spacing: 0) {
                if config.engineMode == "cloud" {
                    PickerRow(
                        title: "Mode · 模式",
                        options: modeOptions,
                        selection: Binding(
                            get: { config.modeId },
                            set: { config.modeId = $0 }
                        )
                    )
                    Divider().background(palette.divider)
                    asrEngineRow
                    Divider().background(palette.divider)
                }
                LocalePickerRow(
                    locales: effectiveLocales,
                    selection: Binding(
                        get: { config.localeId },
                        set: { config.localeId = $0 }
                    )
                )
            }
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .stroke(palette.divider, lineWidth: 0.5)
            )

            // Legend — only relevant for SFSpeechRecognizer path (iOS 18–25)
            if #unavailable(iOS 26) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "iphone")
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.success)
                    Text("端侧识别 · On-device")
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Image(systemName: "cloud")
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.warning)
                    Text("需联网 · Cloud fallback")
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.horizontal, Spacing.xs)
            }
        }
    }

    /// ASR engine row — adapts to OS version:
    /// • iOS 26+: shows a badge indicating SpeechAnalyzer is active (always on-device).
    /// • iOS 18–25: shows a toggle to force on-device recognition only.
    @ViewBuilder
    private var asrEngineRow: some View {
        if #available(iOS 26, *) {
            HStack(spacing: Spacing.sm) {
                Text("识别引擎 · Engine")
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "iphone.badge.checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.success)
                    Text("SpeechAnalyzer · 始终端侧")
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.success)
                }
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, 4)
                .background(palette.success.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        } else {
            Toggle(isOn: Binding(
                get: { config.requiresOnDevice },
                set: { config.requiresOnDevice = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("仅端侧识别 · On-device only")
                        .font(TypeStyle.body)
                        .foregroundStyle(palette.textPrimary)
                    Text("禁用云端回退，识别失败时会报错而非联网 · Disable cloud fallback, fail locally instead of going online")
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .tint(palette.accent)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
    }

    /// Falls back to a static list while SFSpeechRecognizer locales are loading.
    private var effectiveLocales: [(id: String, label: String, onDevice: Bool)] {
        dynamicLocales.isEmpty ? staticLocales : dynamicLocales
    }

    private var staticLocales: [(id: String, label: String, onDevice: Bool)] {
        [
            ("auto",     "Auto · 跟随系统", false),
            ("zh-Hans",  "中文(简体)",      false),
            ("zh-Hant",  "中文(繁體)",      false),
            ("en-US",    "English (US)",    false),
            ("ja-JP",    "日本語",          false),
            ("ko-KR",    "한국어",          false)
        ]
    }

    private var modeOptions: [(id: String, label: String)] {
        [
            ("off",        "Off · 关闭"),
            ("transcribe", "Transcribe · 仅转写"),
            ("polish",     "Polish · 润色")
        ]
    }

    // MARK: - Dynamic locale loading

    private func loadDynamicLocales() async {
        // Run everything in a background task: SFSpeechRecognizer.supportedLocales()
        // can return 100+ locales, and we probe supportsOnDeviceRecognition for each.
        // Creating SFSpeechRecognizer instances in a @Sendable closure is safe —
        // the existing ASRService.swift does the same thing inside AsyncStream { }.
        let entries: [(id: String, label: String, onDevice: Bool)] = await Task.detached(
            priority: .userInitiated
        ) {
            var result: [(id: String, label: String, onDevice: Bool)] = []
            result.append(("auto", "Auto · 跟随系统", false))

            let currentLocale = Locale.current  // snapshot on background thread is fine
            for locale in SFSpeechRecognizer.supportedLocales()
                                             .sorted(by: { $0.identifier < $1.identifier }) {
                let id = locale.identifier
                let onDevice = SFSpeechRecognizer(locale: locale)?.supportsOnDeviceRecognition ?? false
                // localizedString on Locale.current gives the name in the app's UI language.
                let displayName = currentLocale.localizedString(forIdentifier: id) ?? id
                result.append((id: id, label: displayName, onDevice: onDevice))
            }
            return result
        }.value

        // .task {} calls us from the main actor, so this assignment is safe.
        dynamicLocales = entries
    }

    // MARK: - Prompt

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                sectionHeader("System Prompt · 系统提示", subtitle: nil)
                Spacer()
                Button("重置 · Reset") { config.systemPrompt = config.defaultSystemPrompt }
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.accent)
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                TextEditor(text: $config.systemPrompt)
                    .font(TypeStyle.mono)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
                    .padding(Spacing.xs)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                            .stroke(palette.divider, lineWidth: 0.5)
                    )
            }
            .cardSurface()
        }
    }

    // MARK: - Reset

    private var resetButton: some View {
        Button(role: .destructive) {
            showResetConfirm = true
        } label: {
            Text("重置所有设置 · Reset all settings")
                .font(TypeStyle.caption)
                .foregroundStyle(palette.danger)
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Header

    private func sectionHeader(_ title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textSecondary)
                .textCase(.uppercase)
            if let subtitle {
                Text(subtitle)
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Picker row (generic)

private struct PickerRow: View {
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
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    private var currentLabel: String {
        options.first(where: { $0.id == selection })?.label ?? "—"
    }
}

// MARK: - Locale picker row (with on-device indicator)

private struct LocalePickerRow: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    let locales: [(id: String, label: String, onDevice: Bool)]
    @Binding var selection: String

    var body: some View {
        HStack {
            Text("ASR locale · 识别语言")
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
                        if locale.id == selection {
                            Label(locale.label, systemImage: "checkmark")
                        } else if locale.onDevice {
                            Label(locale.label, systemImage: "iphone")
                        } else {
                            Text(locale.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    // On-device badge for the currently selected locale.
                    if let current = locales.first(where: { $0.id == selection }), current.onDevice {
                        Image(systemName: "iphone")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.success)
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
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    private var currentLabel: String {
        locales.first(where: { $0.id == selection })?.label ?? "—"
    }
}
