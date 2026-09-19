// ProviderPickerSection.swift
// OSGKeyboard · Main App

import OSGKeyboardShared
import SwiftUI

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
        HStack(spacing: Spacing.lg) {
            Text(AppL10n.string("settings.provider.supplier"))
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: Spacing.sm)

            Menu {
                Picker("", selection: providerSelection) {
                    ForEach(visiblePresets, id: \.id) { provider in
                        Text(ProviderDisplayName.name(for: provider.id))
                            .tag(provider.id)
                    }
                }
                .labelsHidden()
            } label: {
                providerChip
            }
            .buttonStyle(.plain)
        }
        .settingsListRow()
        .surfaceCard(enabled: showsSurface)
    }

    private var providerSelection: Binding<String> {
        Binding(
            get: { selectedProviderId },
            set: { providerID in
                guard let provider = visiblePresets.first(where: { $0.id == providerID }) else {
                    return
                }
                select(provider)
            }
        )
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

    /// 收起状态展示：当前所选供应商名称、能力标记与展开箭头。
    private var providerChip: some View {
        HStack(spacing: Spacing.sm) {
            Text(ProviderDisplayName.name(for: selectedProvider.id))
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)

            if selectedProvider.supportsPersonalDictionaryCloudASR {
                personalDictionaryBadge
            }
            if role == .asr, selectedProvider.supportsStreamingCloudASR {
                streamingBadge
            }

            Image(systemName: "chevron.up.chevron.down")
                .font(TypeStyle.caption.weight(.semibold))
                .foregroundStyle(palette.textTertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    /// 通义千问 / 智谱 GLM 等支持云端 ASR 热词 API 的提供商。
    private var personalDictionaryBadge: some View {
        Text(AppL10n.string("settings.provider.personalDictionaryBadge"))
            .font(TypeStyle.caption2)
            .foregroundStyle(palette.accent)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 4)
            .background(palette.accentMuted, in: Capsule())
            .lineLimit(1)
    }

    /// Bailian / Volcengine / OpenAI Realtime — utterance-level true streaming.
    private var streamingBadge: some View {
        Text(AppL10n.string("settings.provider.streamingBadge"))
            .font(TypeStyle.caption2)
            .foregroundStyle(palette.accent)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 4)
            .background(palette.accentMuted, in: Capsule())
            .lineLimit(1)
    }
}
