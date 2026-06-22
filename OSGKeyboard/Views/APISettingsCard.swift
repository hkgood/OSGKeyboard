// APISettingsCard.swift
// OSGKeyboard · Main App
//
// Editable fields for the three OpenAI-compatible config values:
// Base URL, API Key, Model.

import SwiftUI
import OSGKeyboardShared

struct APISettingsCard: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject var config: ProviderConfig
    @State private var showKey: Bool = false
    @State private var testStatus: TestStatus = .idle

    private enum TestStatus: Equatable {
        case idle
        case running
        case success
        case failure(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            field(
                title: AppL10n.string("api.baseUrl"),
                placeholder: "https://api.openai.com/v1",
                text: $config.baseURL,
                autocap: false
            )
            Divider().background(palette.divider)
            keyField
            Divider().background(palette.divider)
            field(
                title: AppL10n.string("api.model"),
                placeholder: "gpt-4o-mini",
                text: $config.model,
                autocap: false
            )
            if let url = LLMProvider.provider(id: config.providerId).apiKeyURL {
                Divider().background(palette.divider)
                // Use a Button + UIApplication.open instead of SwiftUI
                // `Link`. SwiftUI `Link` can have hit-test quirks on some
                // makes its tappable area eat gestures from the adjacent
                // TextField, which manifests as "typing jumps to a website".
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    HStack {
                        Text("api.getKey")
                            .font(TypeStyle.body)
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(palette.textSecondary)
                    }
                    .padding(.horizontal, Spacing.md)
                    .frame(minHeight: SettingsListMetrics.singleLineMinHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Divider().background(palette.divider)
            testConnectionRow
        }
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .stroke(palette.divider, lineWidth: 0.5)
        )
    }

    // MARK: - Key

    private var keyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("api.key")
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Button(action: { showKey.toggle() }) {
                    Image(systemName: showKey ? "eye.slash.fill" : "eye.fill")
                        .foregroundStyle(palette.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(showKey
                    ? AppL10n.string("api.key.hide")
                    : AppL10n.string("api.key.show")))
            }
            Group {
                if showKey {
                    TextField("sk-…", text: $config.apiKey)
                } else {
                    SecureField("sk-…", text: $config.apiKey)
                }
            }
            .keyboardType(.asciiCapable)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .font(TypeStyle.body)
            .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: SettingsListMetrics.doubleLineMinHeight, alignment: .center)
    }

    // MARK: - Generic field

    @ViewBuilder
    private func field(
        title: String,
        placeholder: String,
        text: Binding<String>,
        autocap: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textSecondary)
            TextField(placeholder, text: text)
                .keyboardType(.asciiCapable)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(autocap ? .sentences : .never)
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
                .submitLabel(.done)
                .onSubmit { /* no-op: prevent the keyboard from "submitting"
                              and dismissing the sheet unexpectedly */ }
        }
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: SettingsListMetrics.doubleLineMinHeight, alignment: .center)
    }

    // MARK: - Test connection

    private var testConnectionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("api.connection")
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Button(action: runTest) {
                    Group {
                        if testStatus == .running {
                            ProgressView().controlSize(.mini)
                        } else {
                            Text(testButtonLabel)
                                .font(TypeStyle.body)
                                .foregroundStyle(testTint)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(testStatus == .running)
            }
            if let detail = testDetail {
                Text(detail)
                    .font(TypeStyle.caption2)
                    .foregroundStyle(testTint)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: SettingsListMetrics.singleLineMinHeight, alignment: .center)
    }

    private var testButtonLabel: String {
        switch testStatus {
        case .idle:        return AppL10n.string("api.test.idle")
        case .running:     return AppL10n.string("api.test.running")
        case .success:     return AppL10n.string("api.test.success")
        case .failure:     return AppL10n.string("api.test.failure")
        }
    }

    private var testTint: Color {
        switch testStatus {
        case .idle, .running: return palette.accent
        case .success:        return palette.accent
        case .failure:        return palette.danger
        }
    }

    private var testDetail: String? {
        switch testStatus {
        case .idle, .running, .success: return nil
        case .failure(let message): return message
        }
    }

    private func runTest() {
        testStatus = .running
        let store = AppGroupStore()
        let client = OpenAICompatibleClient(
            baseURL: store.baseURL,
            apiKey: store.apiKey,
            model: store.model
        )
        Task {
            do {
                _ = try await client.polish("ping", systemPrompt: "Reply with the single word PONG.")
                testStatus = .success
            } catch LLMError.noAPIKey {
                testStatus = .failure(AppL10n.string("api.test.missing"))
            } catch let error as LLMError {
                switch error {
                case .http(let status):
                    testStatus = .failure(AppL10n.format("api.test.http", status))
                case .rateLimited:
                    testStatus = .failure(AppL10n.string("api.test.rateLimited"))
                case .transport(let msg):
                    testStatus = .failure(AppL10n.format("api.test.transportWith", msg))
                default:
                    testStatus = .failure(error.errorDescription ?? "\(error)")
                }
            } catch {
                testStatus = .failure((error as? LocalizedError)?.errorDescription ?? "\(error)")
            }
        }
    }
}
