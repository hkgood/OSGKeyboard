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
        VStack(alignment: .leading, spacing: SettingsListMetrics.sectionLabelSpacing) {
            sectionHeader("settings.engine.title")
            VStack(spacing: 0) {
                engineOptionRow(
                    id: "local",
                    assetName: "apple",
                    title: NSLocalizedString("settings.engine.local.title", comment: ""),
                    subtitle: localSubtitle
                )
                Divider().background(palette.divider)
                engineOptionRow(
                    id: "cloud",
                    systemIcon: "wand.and.stars",
                    title: NSLocalizedString("settings.engine.cloud.title", comment: ""),
                    subtitle: NSLocalizedString("settings.engine.cloud.subtitle", comment: "")
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
        NSLocalizedString("settings.engine.local.ios26", comment: "")
    }

    private func engineOptionRow(
        id: String,
        assetName: String? = nil,
        systemIcon: String? = nil,
        title: String,
        subtitle: String
    ) -> some View {
        let isSelected = config.engineMode == id
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                config.engineMode = id
                if id == "local" { config.modeId = "transcribe" }
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                engineMark(
                    assetName: assetName,
                    systemIcon: systemIcon,
                    isSelected: isSelected
                )
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
            .frame(minHeight: SettingsListMetrics.doubleLineMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func engineMark(assetName: String?, systemIcon: String?, isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isSelected ? palette.accentMuted : palette.surfaceElevated)
                .frame(width: 32, height: 32)
            if let assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(isSelected ? palette.accent : palette.textPrimary)
            } else if let systemIcon {
                Image(systemName: systemIcon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? palette.accent : palette.textSecondary)
            }
        }
        .frame(width: 32, height: 32)
    }

    @ViewBuilder
    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(TypeStyle.caption2)
            .foregroundStyle(palette.textSecondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
