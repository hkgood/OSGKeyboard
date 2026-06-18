// SettingsView.swift
// OSGKeyboard · Main App
//
// Sheet that hosts the API configuration. Single scrollable column, every
// field earns its space.

import SwiftUI
import OSGKeyboardShared

struct SettingsView: View {
    @ObservedObject var config = ProviderConfig.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: Spacing.md) {
                        providerSection
                        apiSection
                        languageSection
                        promptSection
                        resetButton
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.md)
                }
            }
            .navigationTitle("设置 · Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(TypeStyle.headline)
                        .foregroundStyle(Palette.accent)
                }
            }
        }
        .confirmationDialog(
            "Reset all settings?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                config.reset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("API key, model, and base URL will be cleared.")
        }
    }

    // MARK: - Provider

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader("Provider · 提供商", subtitle: "Pick the LLM that polishes your dictation.")
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
            sectionHeader("Language · 语言", subtitle: "Choose ASR locale and dictation mode.")
            VStack(spacing: 0) {
                PickerRow(
                    title: "Mode",
                    options: modeOptions,
                    selection: Binding(
                        get: { config.modeId },
                        set: { config.modeId = $0 }
                    )
                )
                Divider().background(Palette.divider)
                PickerRow(
                    title: "ASR locale",
                    options: localeOptions,
                    selection: Binding(
                        get: { config.localeId },
                        set: { config.localeId = $0 }
                    )
                )
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .stroke(Palette.divider, lineWidth: 0.5)
            )
        }
    }

    private var modeOptions: [(id: String, label: String)] {
        [
            ("off",        "Off · 关闭"),
            ("transcribe", "Transcribe · 仅转写"),
            ("polish",     "Polish · 润色")
        ]
    }

    private var localeOptions: [(id: String, label: String)] {
        [
            ("auto",     "Auto · 跟随系统"),
            ("zh-Hans",  "中文(简体)"),
            ("zh-Hant",  "中文(繁體)"),
            ("en-US",    "English (US)"),
            ("ja-JP",    "日本語"),
            ("ko-KR",    "한국어")
        ]
    }

    // MARK: - Prompt

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                sectionHeader("System Prompt · 系统提示", subtitle: nil)
                Spacer()
                Button("Reset") { config.systemPrompt = config.defaultSystemPrompt }
                    .font(TypeStyle.caption2)
                    .foregroundStyle(Palette.accent)
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                TextEditor(text: $config.systemPrompt)
                    .font(TypeStyle.mono)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
                    .padding(Spacing.xs)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                            .stroke(Palette.divider, lineWidth: 0.5)
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
            Text("Reset all settings")
                .font(TypeStyle.caption)
                .foregroundStyle(Palette.danger)
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Header

    private func sectionHeader(_ title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(TypeStyle.caption2)
                .foregroundStyle(Palette.textSecondary)
                .textCase(.uppercase)
            if let subtitle {
                Text(subtitle)
                    .font(TypeStyle.caption2)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Picker row

private struct PickerRow: View {
    let title: String
    let options: [(id: String, label: String)]
    @Binding var selection: String

    var body: some View {
        HStack {
            Text(title)
                .font(TypeStyle.body)
                .foregroundStyle(Palette.textPrimary)
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
                        .foregroundStyle(Palette.textSecondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.textTertiary)
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
