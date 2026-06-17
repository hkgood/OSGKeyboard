// APISettingsCard.swift
// OSGKeyboard · Main App
//
// Editable fields for the four OpenAI-compatible config values:
// Base URL, API Key, Model, System Prompt.

import SwiftUI
import OSGKeyboardShared

struct APISettingsCard: View {
    @ObservedObject var config: ProviderConfig
    @State private var showKey: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Base URL", text: $config.baseURL, isSecure: false,
                  keyboard: .URL, autocap: false)
            keyField
            field("Model", text: $config.model, isSecure: false,
                  keyboard: .default, autocap: false)

            VStack(alignment: .leading, spacing: 4) {
                Text("System Prompt")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                TextEditor(text: $config.systemPrompt)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .padding(8)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                Button("Reset to default") {
                    config.systemPrompt = config.defaultSystemPrompt
                }
                .font(.caption2)
                .foregroundStyle(Theme.accent)
            }

            if let url = LLMProvider.provider(id: config.providerId).apiKeyURL {
                Link(destination: url) {
                    Label("Get an API key", systemImage: "key.fill")
                        .font(.caption)
                }
            }
        }
        .cardStyle()
    }

    private var keyField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("API Key")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button(action: { showKey.toggle() }) {
                    Image(systemName: showKey ? "eye.slash.fill" : "eye.fill")
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            Group {
                if showKey {
                    TextField("sk-...", text: $config.apiKey)
                } else {
                    SecureField("sk-...", text: $config.apiKey)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .padding(10)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func field(
        _ title: String,
        text: Binding<String>,
        isSecure: Bool,
        keyboard: UIKeyboardType,
        autocap: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Group {
                if isSecure {
                    SecureField("", text: text)
                } else {
                    TextField("", text: text)
                        .keyboardType(keyboard)
                        .autocorrectionDisabled(true)
                }
            }
            .textInputAutocapitalization(autocap ? .sentences : .never)
            .padding(10)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
