// ProviderPickerSection.swift
// OSGKeyboard · Main App
//
// Provider picker shown inline inside Settings & Onboarding. Each option
// surfaces the provider's name + a short blurb so the user can pick
// confidently without opening a doc.

import SwiftUI
import OSGKeyboardShared

struct ProviderPickerSection: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject var config: ProviderConfig

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(LLMProvider.presets.enumerated()), id: \.element.id) { index, provider in
                Button {
                    select(provider)
                } label: {
                    row(provider, selected: provider.id == config.providerId)
                }
                .buttonStyle(.plain)
                if index < LLMProvider.presets.count - 1 {
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
        HStack(spacing: Spacing.xs) {
            // Provider mark — a coloured dot with first letter
            ZStack {
                Circle()
                    .fill(selected ? palette.accent : palette.surfaceElevated)
                    .frame(width: 36, height: 36)
                Text(String(provider.name.prefix(1)))
                    .font(TypeStyle.bodyEmph)
                    .foregroundStyle(selected ? palette.textOnAccent : palette.textPrimary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                    .font(TypeStyle.bodyEmph)
                    .foregroundStyle(palette.textPrimary)
                if let blurb = provider.blurb {
                    Text(blurb)
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(palette.accent)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())
    }
}
