// KeyboardPreviewSheet.swift
// OSGKeyboard · Main App (Debug)
//
// In-app preview of the keyboard extension. Renders a stand-in
// `KeyboardPreviewStub` so the user can see what the real extension
// looks like, AND drives a *real* `PreviewASRController` so tapping
// the disc actually records from the mic and runs the shared ASR
// service (`SpeechAnalyzer` on iOS 26+),
// and lands recognized text in the top textbox. Without the real ASR
// the preview was a static mock — "the text never appears" was a
// fair review note.
//
// Lifecycle (local engine = "transcribe" only, no LLM):
//   tap → start ASR (idempotent re-entry guard)
//        → ASR emits .partial / .final
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
                    Text("preview.title")
                        .font(TypeStyle.title2)
                        .foregroundStyle(palette.textPrimary)
                    Text("preview.subtitle")
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
        // Tear down the ASR pipeline when the sheet leaves the screen
        // (preview dismissed, app backgrounded mid-recording, etc.).
        // Without this, a leftover `asrTask` keeps the AVAudioSession
        // active and the mic permission in use after the user has
        // moved on. `asr.stop()` is idempotent — it no-ops on
        // `.idle`/`.denied`/`.error` — so it's safe to call here
        // even when the disc is not currently recording.
        .onDisappear {
            asr.stop()
        }
    }

    /// Real `TextField` (was a static placeholder HStack before the
    /// first fix). The user can both type into it AND see recognized
    /// text land in it as the real ASR fires `.final`.
    private var mockTextField: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "text.cursor")
                .foregroundStyle(palette.textSecondary)
            TextField(LocalizedStringKey("preview.placeholder"), text: $typedText, axis: .vertical)
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
                .accessibilityLabel("preview.clear")
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
                modeId: config.modeId,
                localeId: config.localeId,
                onTap: cyclePhase,
                openSettings: { showSettings = true },
                onModeCycle: cycleMode,
                onLocaleCycle: cycleLocale
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

    /// Cycle the input mode on tap of the mode chip. The order mirrors
    /// the Settings picker (`off` → `transcribe` → `polish` → wrap)
    /// so the user sees the same surface in both places.
    ///
    /// Note: when the user picks `off` we *also* stop any in-flight
    /// recording — leaving the disc mid-recording in an "off" mode
    /// would be a confusing state (the user is recording but the
    /// keyboard says it won't insert anything).
    private func cycleMode() {
        let order = ["off", "transcribe", "polish"]
        let current = order.firstIndex(of: config.modeId) ?? 0
        let next = order[(current + 1) % order.count]
        config.modeId = next
        if next == "off" && asr.phase == .recording {
            asr.stop()
        }
    }

    /// Cycle the locale on tap of the locale chip. Same order as
    /// `staticLocales` in `SettingsView.swift` so both surfaces stay
    /// in sync. When the user picks a new locale we *also* stop any
    /// in-flight recording — ASR sessions are bound to the locale
    /// they were started with, and continuing to feed buffers into a
    /// stale session would produce garbage in the next `.final`.
    private func cycleLocale() {
        let order = ["auto", "zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
        let current = order.firstIndex(of: config.localeId) ?? 0
        let next = order[(current + 1) % order.count]
        config.localeId = next
        if asr.phase == .recording {
            asr.stop()
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
