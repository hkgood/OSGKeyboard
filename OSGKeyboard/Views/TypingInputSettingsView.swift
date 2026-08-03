// TypingInputSettingsView.swift
// OSGKeyboard · Main App
//
// Schema and opt-in fuzzy-pinyin settings. Changing fuzzy pairs triggers
// host-side redeployment; the keyboard extension never compiles schemas.

import SwiftUI
import OSGKeyboardShared

struct TypingInputSettingsView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @ObservedObject private var configuration = TypingInputConfiguration.shared

    @State private var isDeploying = false
    @State private var deploymentError: String?

    var body: some View {
        List {
            Section("输入方案") {
                Picker("拼音方案", selection: $configuration.schema) {
                    ForEach(TypingInputSchema.allCases) { schema in
                        Text(schema.displayName).tag(schema)
                    }
                }
                .pickerStyle(.inline)
            }

            Section {
                ForEach(PinyinFuzzyPair.allCases) { pair in
                    Toggle(
                        pair.displayName,
                        isOn: Binding(
                            get: { configuration.fuzzyPairs.contains(pair) },
                            set: { enabled in
                                configuration.setFuzzyPair(pair, enabled: enabled)
                                deployUpdatedSchemas()
                            }
                        )
                    )
                }
            } header: {
                Text("模糊音")
            } footer: {
                Text("默认全部关闭。只开启你需要的组合，避免候选噪音。")
            }

            Section("输入法资源") {
                HStack {
                    Text("状态")
                    Spacer()
                    if isDeploying {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(statusText)
                            .foregroundStyle(
                                deploymentError == nil ? palette.textSecondary : palette.danger
                            )
                    }
                }

                Button("重新部署输入法资源") {
                    deployUpdatedSchemas()
                }
                .disabled(isDeploying)
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle("settings.typingInput.title")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusText: String {
        if let deploymentError { return deploymentError }
        return RimeResourceInstaller.isReady ? "已就绪" : "待初始化"
    }

    private func deployUpdatedSchemas() {
        guard !isDeploying else { return }
        let snapshot = configuration.snapshot
        isDeploying = true
        deploymentError = nil
        Task {
            do {
                try await RimeResourceInstaller.shared.installIfNeeded(
                    configuration: snapshot,
                    force: true
                )
            } catch {
                deploymentError = error.localizedDescription
            }
            isDeploying = false
        }
    }
}
