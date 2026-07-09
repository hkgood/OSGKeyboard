// ProviderPickerSection.swift
// OSGKeyboard · Main App

import SwiftUI
import OSGKeyboardShared

struct ProviderPickerSection: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject var config: ProviderConfig

    var body: some View {
        // v0.2.1 follow-up: filter out presets marked as
        // `isUserSelectable == false` (DeepSeek is local-engine only).
        let visiblePresets = LLMProvider.userSelectablePresets
        VStack(spacing: 0) {
            ForEach(Array(visiblePresets.enumerated()), id: \.element.id) { index, provider in
                Button {
                    select(provider)
                } label: {
                    row(provider, selected: provider.id == config.providerId)
                }
                .buttonStyle(.plain)
                if index < visiblePresets.count - 1 {
                    Divider().background(palette.divider)
                }
            }
        }
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .stroke(palette.divider, lineWidth: 0.5)
        )
    }

    private func select(_ provider: LLMProvider) {
        withAnimation(Motion.quick) {
            config.apply(preset: provider)
        }
    }

    @ViewBuilder
    private func row(_ provider: LLMProvider, selected: Bool) -> some View {
        HStack(spacing: Spacing.sm) {
            providerMark(provider, selected: selected)

            Text(ProviderDisplayName.name(for: provider.id))
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)

            if provider.supportsPersonalDictionaryCloudASR {
                personalDictionaryBadge
            }

            Spacer(minLength: Spacing.xs)

            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(palette.accent)
            }
        }
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: SettingsListMetrics.singleLineMinHeight)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func providerMark(_ provider: LLMProvider, selected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(selected ? palette.accentMuted : palette.surfaceElevated)
                .frame(width: 32, height: 32)
            if let asset = ProviderLogo.assetName(for: provider.id) {
                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(selected ? palette.accent : palette.textPrimary)
            } else {
                Text(String(provider.name.prefix(1)))
                    .font(TypeStyle.caption)
                    .foregroundStyle(selected ? palette.accent : palette.textSecondary)
            }
        }
    }

    /// 通义千问 / 智谱 GLM 等支持云端 ASR 热词 API 的提供商。
    private var personalDictionaryBadge: some View {
        Text("settings.provider.personalDictionaryBadge")
            .font(TypeStyle.caption2)
            .foregroundStyle(palette.accent)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 4)
            .background(palette.accentMuted, in: Capsule())
    }
}
