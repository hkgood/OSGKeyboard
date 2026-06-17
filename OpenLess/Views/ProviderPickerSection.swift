// ProviderPickerSection.swift
// OSGKeyboard · Main App
//
// A picker that swaps in the right BaseURL/Model defaults for a chosen
// provider, while letting the user override each field.

import SwiftUI
import OSGKeyboardShared

struct ProviderPickerSection: View {
    @ObservedObject var config: ProviderConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Provider")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }

            Picker("Provider", selection: $config.providerId) {
                ForEach(LLMProvider.presets) { p in
                    Text(p.name).tag(p.id)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.accent)
            .onChange(of: config.providerId) { _, newId in
                let preset = LLMProvider.provider(id: newId)
                config.apply(preset: preset)
            }
        }
        .cardStyle()
    }
}
