// ProviderPickerSection.swift
// OSGKeyboard · Main App

import SwiftUI
import OSGKeyboardShared

struct ProviderPickerSection: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject var config: ProviderConfig
    var role: CloudProviderRole = .polish
    /// 嵌入合并卡片时为 `false`，由外层统一绘制圆角背景。
    var showsSurface: Bool = true

    private var selectedProviderId: String {
        role == .asr ? config.asrProviderId : config.providerId
    }

    private var visiblePresets: [LLMProvider] {
        role == .asr
            ? LLMProvider.asrSelectablePresets
            : LLMProvider.userSelectablePresets
    }

    private var selectedProvider: LLMProvider {
        visiblePresets.first(where: { $0.id == selectedProviderId })
            ?? LLMProvider.provider(id: selectedProviderId)
    }

    var body: some View {
        // 只有右侧芯片是 Menu 的 label；标题留在行外，避免菜单弹出时
        // 把整行 label 一起隐藏，导致左侧「供应商」文字消失。
        SettingsProviderRow(title: AppL10n.string("settings.provider.supplier")) {
            Menu {
                ForEach(visiblePresets, id: \.id) { provider in
                    Button {
                        select(provider)
                    } label: {
                        let name = ProviderDisplayName.name(for: provider.id)
                        if provider.id == selectedProviderId {
                            Label(name, systemImage: "checkmark")
                        } else {
                            Text(name)
                        }
                    }
                }
            } label: {
                providerChip
            }
            .buttonStyle(.plain)
        }
        .modifier(SettingsSurfaceCardModifier(enabled: showsSurface))
    }

    private func select(_ provider: LLMProvider) {
        withAnimation(Motion.quick) {
            switch role {
            case .polish:
                config.apply(preset: provider)
            case .asr:
                config.applyAsr(preset: provider)
            }
        }
    }

    /// 收起状态展示：当前所选供应商 logo + 名称 + 展开箭头。
    private var providerChip: some View {
        HStack(spacing: Spacing.sm) {
            providerMark(selectedProvider)

            Text(ProviderDisplayName.name(for: selectedProvider.id))
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)

            if selectedProvider.supportsPersonalDictionaryCloudASR {
                personalDictionaryBadge
            }

            Spacer(minLength: Spacing.xs)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func providerMark(_ provider: LLMProvider) -> some View {
        ZStack {
            Circle()
                .fill(palette.accentMuted)
                .frame(width: 32, height: 32)
            if let asset = ProviderLogo.assetName(for: provider.id) {
                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(palette.accent)
            } else {
                Text(String(provider.name.prefix(1)))
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.accent)
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
