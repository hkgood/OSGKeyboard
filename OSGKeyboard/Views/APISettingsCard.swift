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
        case success(String)
        case failure(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            field(
                title: "Base URL · 接口地址",
                placeholder: "https://api.openai.com/v1",
                text: $config.baseURL,
                autocap: false
            )
            Divider().background(palette.divider)
            keyField
            Divider().background(palette.divider)
            field(
                title: "Model · 模型",
                placeholder: "gpt-4o-mini",
                text: $config.model,
                autocap: false
            )
            if let url = LLMProvider.provider(id: config.providerId).apiKeyURL {
                Divider().background(palette.divider)
                // Use a Button + UIApplication.open instead of SwiftUI
                // `Link`. SwiftUI `Link` has a hit-test bug on iOS 18 that
                // makes its tappable area eat gestures from the adjacent
                // TextField, which manifests as "typing jumps to a website".
                Button {
                    UIApplication.shared.open(url)
                } label: {
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundStyle(palette.accent)
                        Text("api.getKey")
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(palette.textSecondary)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
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
                .accessibilityLabel(Text(showKey ? "隐藏密钥 · Hide key" : "显示密钥 · Show key"))
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
        .padding(.vertical, Spacing.sm)
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
            // `.asciiCapable` is the *minimum* contract for these fields:
            // API keys, base URLs, and model names are all ASCII by spec,
            // and SwiftUI's `.URL` keyboard on iOS 18 still occasionally
            // hands control to the system keyboard which then auto-suggests
            // Chinese / emoji completions that corrupt the value. Forcing
            // `.asciiCapable` keeps the system out of the way.
            TextField(placeholder, text: text)
                .keyboardType(.asciiCapable)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(autocap ? .sentences : .never)
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
                .submitLabel(.done)
                .onSubmit { /* no-op: prevent the keyboard from "submitting"
                              and dismissing the sheet on iOS 18 */ }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Test connection

    private var testConnectionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("api.connection")
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                Button(action: runTest) {
                    HStack(spacing: 6) {
                        if testStatus == .running {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: testIcon)
                                .foregroundStyle(testTint)
                        }
                        Text(testButtonLabel)
                            .font(TypeStyle.caption)
                            .foregroundStyle(testTint)
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
        .padding(.vertical, Spacing.sm)
    }

    private var testButtonLabel: String {
        switch testStatus {
        case .idle:        return NSLocalizedString("api.test.idle", comment: "")
        case .running:     return NSLocalizedString("api.test.running", comment: "")
        case .success:     return NSLocalizedString("api.test.success", comment: "")
        case .failure:     return NSLocalizedString("api.test.failure", comment: "")
        }
    }

    private var testIcon: String {
        switch testStatus {
        case .idle, .running: return "bolt.horizontal.circle"
        case .success:        return "checkmark.circle.fill"
        case .failure:        return "exclamationmark.triangle.fill"
        }
    }

    private var testTint: Color {
        switch testStatus {
        case .idle, .running: return palette.accent
        case .success:        return palette.success
        case .failure:        return palette.danger
        }
    }

    private var testDetail: String? {
        switch testStatus {
        case .idle, .running: return nil
        case .success(let s): return s
        case .failure(let s): return s
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
                let reply = try await client.polish("ping", systemPrompt: "Reply with the single word PONG.")
                // Interpolated success message — LocalizedStringKey can't
                // take %@, so we use `String.localizedStringWithFormat`
                // with a key that has %@ in the value.
                let preview = String(reply.prefix(60))
                testStatus = .success(String.localizedStringWithFormat(
                    NSLocalizedString("api.test.connectedWith", comment: "Connected test prefix"),
                    preview
                ))
            } catch LLMError.noAPIKey {
                testStatus = .failure(NSLocalizedString("api.test.missing", comment: ""))
            } catch let error as LLMError {
                switch error {
                case .http(let status):
                    testStatus = .failure(String.localizedStringWithFormat(
                        NSLocalizedString("api.test.http", comment: ""),
                        status
                    ))
                case .rateLimited:
                    testStatus = .failure(NSLocalizedString("api.test.rateLimited", comment: ""))
                case .transport(let msg):
                    testStatus = .failure(String.localizedStringWithFormat(
                        NSLocalizedString("api.test.transportWith", comment: ""),
                        msg
                    ))
                default:
                    testStatus = .failure(error.errorDescription ?? "\(error)")
                }
            } catch {
                testStatus = .failure((error as? LocalizedError)?.errorDescription ?? "\(error)")
            }
        }
    }
}
