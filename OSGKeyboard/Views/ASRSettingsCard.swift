// ASRSettingsCard.swift
// OSGKeyboard · Main App
//
// Cloud ASR credentials — independent from the polish LLM card.

import SwiftUI
import OSGKeyboardShared

struct ASRSettingsCard: View {
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
            if CloudASRModelCatalog.strategy(for: config.asrProviderId) == .prompt {
                field(
                    title: AppL10n.string("api.baseUrl"),
                    placeholder: "https://api.openai.com/v1",
                    text: $config.asrBaseURL,
                    autocap: false
                )
                Divider().background(palette.divider)
            }
            keyField
            Divider().background(palette.divider)
            field(
                title: AppL10n.string("settings.asr.model"),
                placeholder: CloudASRModelCatalog.defaultModel(for: config.asrProviderId),
                text: $config.asrModel,
                autocap: false
            )
            if let url = LLMProvider.provider(id: config.asrProviderId).apiKeyURL {
                Divider().background(palette.divider)
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
            }
            Group {
                if showKey {
                    TextField("sk-…", text: $config.asrApiKey)
                } else {
                    SecureField("sk-…", text: $config.asrApiKey)
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
        }
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: SettingsListMetrics.doubleLineMinHeight, alignment: .center)
    }

    private var testConnectionRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("settings.asr.testConnection")
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
        let client = CloudASRClientFactory.make(store: store)
        Task {
            do {
                try await client.prepare(dictionary: store.personalDictionary)
                let samples = [Float](repeating: 0.01, count: 16_000)
                _ = try await client.transcribe(
                    samples: samples,
                    sampleRate: 16_000,
                    locale: Locale(identifier: store.localeId == "auto" ? "zh-CN" : store.localeId),
                    dictionary: store.personalDictionary
                )
                testStatus = .success
            } catch CloudASRError.noAPIKey {
                testStatus = .failure(AppL10n.string("api.test.missing"))
            } catch let error as CloudASRError {
                testStatus = .failure(error.localizedDescription ?? "\(error)")
            } catch {
                testStatus = .failure((error as? LocalizedError)?.errorDescription ?? "\(error)")
            }
        }
    }
}
