// KeyboardPreviewSheet.swift
// OSGKeyboard · Main App (Debug)
//
// In-app preview of the keyboard extension. Renders a stand-in
// `KeyboardPreviewStub` so the user can see what the real extension
// looks like, AND drives a *real* `PreviewASRController` so tapping
// the disc actually records from the mic, runs SFSpeechRecognizer,
// and lands recognized text in the top textbox. Without the real ASR
// the preview was a static mock — "the text never appears" was a
// fair review note.
//
// Lifecycle (local engine = "transcribe" only, no LLM):
//   tap → start ASR (idempotent re-entry guard)
//        → SFSpeechRecognizer emits .partial / .final
//        → currentPartial updates the transcript line in real time
//   tap → stop ASR
//        → lastFinal event lands
//        → onChange in this view appends to typedText
//        → controller resets

import SwiftUI
import OSGKeyboardShared

struct KeyboardPreviewSheet: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var config = ProviderConfig.shared
    @StateObject private var asr = PreviewASRController()

    @State private var showSettings = false
    /// Accumulates text in the top textbox. The real keyboard extension
    /// inserts directly via `textDocumentProxy`; this preview mirrors
    /// that in a parallel `@State` so the user can verify the flow.
    @State private var typedText: String = ""
    /// Cached snapshot of the previous lastFinal so the .onChange
    /// doesn't fire on every body re-render — only on real changes.
    @State private var lastFinalSeen: String = ""

    private enum StubPhase { case idle, recording, processing }

    /// Visible phase for the stub. Driven by the real ASR controller
    /// — when the controller is `recording` we show the recording
    /// state; otherwise we show `processing` while a final is in
    /// flight and `idle` otherwise.
    private var stubPhase: KeyboardPreviewStub.Phase {
        switch asr.phase {
        case .recording:    return .recording
        case .processing:   return .processing
        case .idle:         return .idle
        case .requestingPermission:
            return .recording
        case .denied, .error:
            return .idle
        }
    }

    /// The transcript line the stub shows under the chips. While
    /// recording we surface the live ASR partial; otherwise we surface
    /// any error or stay quiet.
    private var stubTranscript: String {
        switch asr.phase {
        case .recording:
            return asr.currentPartial.isEmpty ? " " : asr.currentPartial
        case .error(let m):
            return m
        case .denied(let m):
            return m
        default:
            return ""
        }
    }

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: Spacing.md) {
                    Text("键盘预览 · Keyboard Preview")
                        .font(TypeStyle.title2)
                        .foregroundStyle(palette.textPrimary)
                    Text("点按 disc 开始/结束录音;真实键盘使用同样布局。\nTap the disc to start/stop recording. The real keyboard uses the same layout.")
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)
                    mockTextField.padding(.horizontal, Spacing.md)
                }
                .padding(.top, Spacing.lg)
                Spacer(minLength: 0)
                keyboardBlock
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onChange(of: asr.lastFinal) { _, new in
            guard !new.isEmpty, new != lastFinalSeen else { return }
            lastFinalSeen = new
            insertRecognizedText(new)
            asr.reset()
        }
    }

    /// Real `TextField` (was a static placeholder HStack before the
    /// first fix). The user can both type into it AND see recognized
    /// text land in it as the real ASR fires `.final`.
    private var mockTextField: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "text.cursor")
                .foregroundStyle(palette.textSecondary)
            TextField("试着输入或按 disc 录音 · Type or tap to record", text: $typedText, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .foregroundStyle(palette.textPrimary)
                .tint(palette.accent)
            if !typedText.isEmpty {
                Button {
                    typedText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空 · Clear text")
            }
        }
        .padding(Spacing.md)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.medium)
                .stroke(palette.divider, lineWidth: 0.5)
        )
    }

    private var keyboardBlock: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(palette.divider)
                .frame(height: 0.5)
            KeyboardPreviewStub(
                phase: stubPhase,
                level: asr.level,
                transcript: stubTranscript,
                onTap: cyclePhase,
                openSettings: { showSettings = true }
            )
        }
    }

    /// Tap on the disc. Drives the *real* ASR pipeline — the previous
    /// mock that just toggled a hardcoded phase is gone.
    private func cyclePhase() {
        withAnimation(Motion.quick) {
            switch asr.phase {
            case .idle, .denied, .error:
                let locale = resolveLocale(config.localeId)
                Task { await asr.start(locale: locale) }
            case .recording:
                asr.stop()
            case .requestingPermission, .processing:
                break
            }
        }
    }

    private func resolveLocale(_ id: String) -> Locale {
        if id == "auto" { return .current }
        return Locale(identifier: id)
    }

    /// Append the recognized transcript to the textbox, with a leading
    /// space when the existing text doesn't already end in whitespace.
    /// Matches what `textDocumentProxy.insertText` does for the real
    /// keyboard when the user's draft has no trailing whitespace.
    private func insertRecognizedText(_ recognized: String) {
        let trimmed = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if typedText.isEmpty {
            typedText = trimmed
        } else if typedText.last == " " || typedText.last == "\n" {
            typedText += trimmed
        } else {
            typedText += " " + trimmed
        }
    }
}

#if DEBUG
#Preview {
    KeyboardPreviewSheet()
}
#endif
