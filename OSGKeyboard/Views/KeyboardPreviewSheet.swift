// KeyboardPreviewSheet.swift
// OSGKeyboard · Main App (Debug)
//
// In-app preview of the keyboard extension. Drives the shared
// `LiveDictationController` so tapping record exercises the same
// on-device ASR pipeline as host-app dictation handoff.
//
// Local engine: partial transcripts stream into the text box live.
// Cloud engine: final transcript is appended when recording stops.

import SwiftUI
import OSGKeyboardShared

struct KeyboardPreviewSheet: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var config = ProviderConfig.shared
    @StateObject private var dictation = LiveDictationController()

    @State private var showSettings = false
    @State private var typedText: String = ""
    @State private var lastFinalSeen: String = ""
    /// Text in the box when the current dictation session started.
    @State private var dictationAnchorText: String = ""

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            VStack(spacing: Spacing.md) {
                VStack(spacing: Spacing.md) {
                    Text("preview.title")
                        .font(TypeStyle.title2)
                        .foregroundStyle(palette.textPrimary)
                    Text("preview.subtitle")
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)
                    mockTextField.padding(.horizontal, Spacing.md)
                    controls
                        .padding(.horizontal, Spacing.md)
                }
                .padding(.top, Spacing.lg)
                Spacer()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onChange(of: dictation.currentPartial) { _, partial in
            guard config.isLocalEngine, isDictationActive else { return }
            applyLiveTranscript(partial)
        }
        .onChange(of: dictation.lastFinal) { _, new in
            guard !new.isEmpty, new != lastFinalSeen else { return }
            lastFinalSeen = new
            if config.isLocalEngine {
                applyLiveTranscript(new)
                dictationAnchorText = typedText
            } else {
                insertRecognizedText(new)
            }
            dictation.reset()
        }
        .onDisappear {
            dictation.stop()
        }
    }

    private var mockTextField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Image(systemName: "text.cursor")
                    .foregroundStyle(palette.textSecondary)
                Text(statusTitle)
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
                if !typedText.isEmpty {
                    Button {
                        typedText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("preview.clear")
                }
            }
            TextEditor(text: $typedText)
                .frame(minHeight: 260)
                .scrollContentBackground(.hidden)
                .foregroundStyle(palette.textPrimary)
                .tint(palette.accent)
                .padding(.horizontal, 2)
        }
        .padding(Spacing.md)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.medium)
                .stroke(palette.divider, lineWidth: 0.5)
        )
    }

    private var controls: some View {
        VStack(spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Button {
                    toggleRecording()
                } label: {
                    Label(isRecording ? "停止录音" : "开始录音", systemImage: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .primaryButton()
                }
                .buttonStyle(.plain)

                Button {
                    showSettings = true
                } label: {
                    Label("设置", systemImage: "gearshape")
                        .secondaryButton()
                }
                .buttonStyle(.plain)
            }

            Text(serviceLabel)
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }

    private var serviceLabel: String {
        EngineServiceLabel.summary(
            engineMode: config.engineMode,
            providerId: config.providerId,
            model: config.model
        )
    }

    private var isRecording: Bool {
        if case .recording = dictation.phase { return true }
        return false
    }

    private var isDictationActive: Bool {
        switch dictation.phase {
        case .recording, .processing: return true
        default: return false
        }
    }

    private var statusTitle: String {
        switch dictation.phase {
        case .idle: return "输入框"
        case .requestingPermission: return "请求权限中..."
        case .recording: return config.isLocalEngine ? "正在实时识别..." : "正在录音..."
        case .processing: return "识别中..."
        case .denied(let message), .error(let message):
            return message
        }
    }

    private func toggleRecording() {
        withAnimation(Motion.quick) {
            switch dictation.phase {
            case .idle, .denied, .error:
                startRecording()
            case .recording:
                stopAndFinalize()
            case .requestingPermission, .processing:
                break
            }
        }
    }

    private func startRecording() {
        dictationAnchorText = typedText
        lastFinalSeen = ""
        Task { await dictation.start(localeId: config.localeId) }
    }

    private func stopAndFinalize() {
        dictation.stop()
    }

    private func applyLiveTranscript(_ transcript: String) {
        let composed = DictationTextComposer.compose(anchor: dictationAnchorText, live: transcript)
        guard composed != typedText else { return }
        typedText = composed
    }

    private func insertRecognizedText(_ recognized: String) {
        let trimmed = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        typedText = DictationTextComposer.compose(anchor: typedText, live: trimmed)
    }
}

#if DEBUG
#Preview {
    KeyboardPreviewSheet()
}
#endif
