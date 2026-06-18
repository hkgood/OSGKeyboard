// EnginePickerSection.swift
// OSGKeyboard · Main App
//
// Engine picker — Local (on-device ASR, no LLM) vs Cloud (ASR + LLM
// polish). Lives in its own file so the onboarding flow (first-run,
// no API key yet) and the in-app Settings sheet can render the same
// component: both need to expose the same two options, and the user
// must reach the same "Cloud needs an API key" conclusion from either
// entry point.
//
// Selecting "local" also forces `modeId = "transcribe"`: the Local
// engine skips the LLM round-trip, so leaving modeId on `polish`
// would surface a confusing "I set everything up and nothing
// happens" state. The settings UI is the source of truth for
// `engineMode`; the onboarding page mutates the same `ProviderConfig`
// singleton.

import SwiftUI
import OSGKeyboardShared

struct EnginePickerSection: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject var config: ProviderConfig

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader(
                "settings.engine.title",
                subtitle: "settings.engine.subtitle"
            )
            VStack(spacing: 0) {
                engineOptionRow(
                    id: "local",
                    icon: "iphone.badge.checkmark",
                    title: "本地识别 · On-device",
                    subtitle: localSubtitle
                )
                Divider().background(palette.divider)
                engineOptionRow(
                    id: "cloud",
                    icon: "wand.and.stars",
                    title: "云端润色 · Cloud polish",
                    subtitle: "ASR 转录 + LLM 润色,需要 API Key\nASR + LLM polish, API key required"
                )
            }
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .stroke(palette.divider, lineWidth: 0.5)
            )
        }
    }

    private var localSubtitle: String {
        // iOS 26's `SpeechAnalyzer` is always fully on-device, so the
        // local engine's only contract is "no network, no LLM".
        "SpeechAnalyzer · 始终端侧,无需联网\nAlways on-device, no network"
    }

    private func engineOptionRow(id: String, icon: String, title: String, subtitle: String) -> some View {
        let isSelected = config.engineMode == id
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                config.engineMode = id
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

    @ViewBuilder
    private func sectionHeader(_ title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textSecondary)
                .textCase(.uppercase)
            Text(subtitle)
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
