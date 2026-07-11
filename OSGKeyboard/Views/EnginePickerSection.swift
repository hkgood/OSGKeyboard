// EnginePickerSection.swift
// OSGKeyboard · Main App
//
// Engine picker — Local (on-device ASR) vs
// Cloud (ASR + optional LLM polish via the user's API).

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
                    systemIcon: "iphone.badge.checkmark",
                    title: AppL10n.string("settings.engine.local.title"),
                    subtitle: localSubtitle
                )
                Divider().background(palette.divider)
                engineOptionRow(
                    id: "cloud",
                    systemIcon: "wand.and.stars",
                    title: AppL10n.string("settings.engine.cloud.title"),
                    subtitle: AppL10n.string("settings.engine.cloud.subtitle")
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
        AppL10n.string("settings.engine.local.legacy")
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
            guard config.engineMode != id else { return }
            selectEngine(id)
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
            .settingsListRow()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func selectEngine(_ id: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            config.engineMode = id
            if id == "cloud" {
                config.modeId = "polish"
            }
        }
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
