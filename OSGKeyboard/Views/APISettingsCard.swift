// APISettingsCard.swift
// OSGKeyboard · Main App
//
// Editable fields for the three OpenAI-compatible config values:
// Base URL, API Key, Model.

import SwiftUI
import OSGKeyboardShared

struct APISettingsCard: View {
    @ObservedObject var config: ProviderConfig
    @State private var showKey: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            field(
                title: "Base URL",
                placeholder: "https://api.openai.com/v1",
                text: $config.baseURL,
                keyboard: .URL,
                autocap: false
            )
            Divider().background(Palette.divider)
            keyField
            Divider().background(Palette.divider)
            field(
                title: "Model",
                placeholder: "gpt-4o-mini",
                text: $config.model,
                keyboard: .default,
                autocap: false
            )
            if let url = LLMProvider.provider(id: config.providerId).apiKeyURL {
                Divider().background(Palette.divider)
                // Use a Button + UIApplication.open instead of SwiftUI
                // `Link`. SwiftUI `Link` has a hit-test bug on iOS 18 that
                // makes its tappable area eat gestures from the adjacent
                // TextField, which manifests as "typing jumps to a website".
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundStyle(Palette.accent)
                        Text("Get an API key")
                            .foregroundStyle(Palette.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .stroke(Palette.divider, lineWidth: 0.5)
        )
    }

    // MARK: - Key

    private var keyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("API Key")
                    .font(TypeStyle.caption)
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                Button(action: { showKey.toggle() }) {
                    Image(systemName: showKey ? "eye.slash.fill" : "eye.fill")
                        .foregroundStyle(Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(showKey ? "Hide key" : "Show key"))
            }
            Group {
                if showKey {
                    TextField("sk-…", text: $config.apiKey)
                } else {
                    SecureField("sk-…", text: $config.apiKey)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .font(TypeStyle.body)
            .foregroundStyle(Palette.textPrimary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Generic field

    @ViewBuilder
    private func field(
        title: String,
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        autocap: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(TypeStyle.caption)
                .foregroundStyle(Palette.textSecondary)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(autocap ? .sentences : .never)
                .font(TypeStyle.body)
                .foregroundStyle(Palette.textPrimary)
                .submitLabel(.done)
                .onSubmit { /* no-op: prevent the keyboard from "submitting"
                              and dismissing the sheet on iOS 18 */ }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}
